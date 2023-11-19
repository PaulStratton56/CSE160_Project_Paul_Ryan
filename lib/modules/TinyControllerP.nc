#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcpack.h"
#include "../../includes/timeStamp.h"

module TinyControllerP{
    provides interface TinyController;

    uses interface Waysender as send;
    
    uses interface Hashmap<port_t> as ports;
    uses interface Hashmap<socket_store_t> as sockets;
    uses interface Queue<uint32_t> as sendQueue; // Queue to send across multiple sockets
    uses interface Queue<tcpack> as receiveQueue; // Queue to receive across multiple sockets
    uses interface Queue<timestamp> as timeQueue; // Queue to retransmit across multiple sockets

    uses interface Timer<TMilli> as timeoutTimer;
    uses interface Timer<TMilli> as sendDelay;
    uses interface Timer<TMilli> as removeDelay; // Timer to remove the socket after moving to WAIT_FINAL state.
    uses interface Timer<TMilli> as closeDelay; // Dummy timer to signal the app has closed to move from CLOSING to CLOSED.

    uses interface Random;
}

implementation{
    tcpack storedMsg;
    uint32_t IDtoClose;//problems
    int timeoutTime;
    uint8_t readDataBuffer[SOCKET_BUFFER_SIZE];
    enum flags{
        EMPTY = 0,
        FIN = 1,
        ACK = 2,
        ACK_FIN = 3,
        SYNC = 4,
        SYNC_FIN = 5,
        SYNC_ACK = 6,
        SYNC_ACK_FIN = 7};

    //Function Declarations
    void createSocket(
        socket_store_t*   socket, 
        // uint8_t           flag, 
        uint8_t           state, 
        socket_port_t     srcPort, 
        socket_port_t     destPort,
        uint8_t           dest,
        uint8_t          destSeq);
    void makeTCPack(
        tcpack* pkt,
        uint8_t sync,
        uint8_t ack,
        uint8_t fin,
        uint8_t size,
        uint32_t socketID,
        byteCount_t adWindow,
        byteCount_t data);
    uint32_t getSocketID(uint8_t dest, uint8_t destPort, uint8_t srcPort);
    uint8_t noData();
    void printSocket(uint32_t socketID);
    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID, uint8_t byte, uint8_t intent);
    uint32_t getSID(tcpack msg);
    void printTimeStamp(timestamp* ts);
    bool isByteinFlight(uint32_t socketID, byteCount_t byte);
    void sendSUTD(uint32_t socketID, uint8_t intent);
    bool needsRetransmit(timestamp ts);
    char* getPrinted(uint8_t value, bool isState);
    void printBuffer(uint8_t* buffer, uint8_t len);

    /* == sendData() ==
        Checks if this node has a socket that wants to send data.
        If there is, then it sends the data. That's it. */
    task void sendData(){
        uint32_t socketID;
        socket_store_t socket;
        uint8_t length;
        tcpack packet;

        //If a socket wants to send data..
        if(call sendQueue.size()>0){
            //Get the socket whose turn it is to send.
            socketID = call sendQueue.dequeue();
            socket = call sockets.get(socketID);

            //This needs to change to sliding window, and must consider wraparound
            if(socket.nextToSend!=socket.nextToWrite){
                timestamp ts;

                //If what the socket needs to send is too big for one packet, then we can only send the payload size as a max.
                length = (((byteCount_t)(socket.nextToWrite-socket.nextToSend))>tc_max_pld_len) ? tc_max_pld_len : ((byteCount_t)(socket.nextToWrite-socket.nextToSend));
                
                //Make and send the packet.
                makeTCPack(&packet,0,0,0,length,socketID, ((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE, socket.nextToSend);
                call send.send(255,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&packet);
                dbg(TRANSPORT_CHANNEL,"INFO (transport): Sent [%d,%d).\n",socket.nextToSend%SOCKET_BUFFER_SIZE, (socket.nextToSend+length)%SOCKET_BUFFER_SIZE);

                //Add a retransmission timestamp for the packet, and call the retransmission timer if not in progress.
                makeTimeStamp(&ts, 2*socket.RTT, socketID, socket.nextToSend, EMPTY);
                call timeQueue.enqueue(ts);
                timeoutTime = (call timeQueue.empty()) ? 2000 : ((call timeQueue.head()).expiration - call timeoutTimer.getNow());
                if(!call timeoutTimer.isRunning()){ call timeoutTimer.startOneShot(timeoutTime); }
                
                //Update the socket with the new "nextToSend"
                socket.nextToSend+=length;
                call sockets.insert(socketID,socket);
            }
            else{ // There's no outbound data from any socket.
                dbg(TRANSPORT_CHANNEL,"No data in sendBuffer of socket %d\n",socketID);
            }
        }
        else{
            dbg(TRANSPORT_CHANNEL,"Nothing in sendQueue\n");
        }
    }

    /* == checkTimeouts ==
        Runs through the timeout queue for bytes. 
        If they haven't been acked and the timeout has expired, then we need to retransmit, so requeue for sending. 
        Posted when the timeoutTimer fires. */
    task void checkTimeouts(){
        int i=0;
        int numInFlight = call timeQueue.size();
        uint32_t currentTime = call timeoutTimer.getNow();

        //Check all timestamps for a timeout.
        for(i=0;i<numInFlight;i++){
            //Get a timestamp, and the socket associated with it.
            timestamp ts = call timeQueue.dequeue();
            socket_store_t socket = call sockets.get(ts.id);

            //If the timestamp is for setup or teardown,
            if(ts.intent != EMPTY){
                //Check if timestamp is still useful.
                if(needsRetransmit(ts)){
                    //Retransmit if the timestamp has expired.
                    if(currentTime > ts.expiration){
                        //Reset the sequence to what it was before.
                        socket.nextToSend--;
                        call sockets.insert(ts.id, socket);
                        dbg(TRANSPORT_CHANNEL, "INFO (timeout): %s expired. NTS: %d\n", getPrinted(ts.intent, FALSE), socket.nextToSend);
                        sendSUTD(ts.id, ts.intent);
                    }
                    else{ //Timestamp still valid, requeue.
                        call timeQueue.enqueue(ts);
                    }
                }
            }
            else{ //Otherwise, is data.
                //If the distance between the last acked byte and the nextToSend byte does not wrap around the buffer,
                if(socket.lastAcked<=socket.nextToSend){
                    //Check if the first byte of the timestamped packet has NOT been acked yet.
                    if(socket.lastAcked<=ts.byte && ts.byte<socket.nextToSend){
                        //If the timestamp has timed out and hasn't been acked, retransmit the data.
                        if(currentTime>ts.expiration){
                            dbg(TRANSPORT_CHANNEL,"INFO (timeout): Bytes [%d,...) expired. LA:%d | byte: %d | NTS: %d | Socket: %d\n", ts.byte%SOCKET_BUFFER_SIZE, socket.lastAcked, ts.byte, socket.nextToSend, ts.id);

                            //Update the socket with the setback (Go Back N style)
                            socket.nextToSend = ts.byte;
                            call sockets.insert(ts.id,socket);

                            //Queue the byte for sending again, NOT for the timeout because it hasn't been sent yet.
                            call sendQueue.enqueue(ts.id);
                            post sendData();
                        }
                        else{ //Not acked, but not expired, so keep it in queue.
                            call timeQueue.enqueue(ts);
                        }
                    }
                    else{ //The byte has been acked. No need to keep the timestamp.
                        // dbg(TRANSPORT_CHANNEL, "INFO (timeout): Data (byte: %d) ACKED. | LA: %d | NTS: %d\n", ts.byte, socket.lastAcked, socket.nextToSend);
                    }
                }
                else{ //The considered window wraps around the buffer.. That's a little trickier
                    //If the byte has NOT been acked yet,
                    if(!(socket.nextToSend<ts.byte && ts.byte<socket.lastAcked)){
                        //If the timestamp hasn't been acked and has timed out, then retransmit.
                        if(currentTime>ts.expiration){
                            dbg(TRANSPORT_CHANNEL,"INFO (timeout): Bytes [%d,...) expired. LA:%d | byte: %d | NTS: %d | Socket: %d\n", ts.byte%SOCKET_BUFFER_SIZE, socket.lastAcked, ts.byte, socket.nextToSend, ts.id);

                            //Update the socket with the setback (Go Back N style)
                            socket.nextToSend = ts.byte;
                            call sockets.insert(ts.id,socket);

                            //Queue the byte for sending again, NOT for the timeout because it hasn't been sent yet.                        
                            call sendQueue.enqueue(ts.id);
                            post sendData();
                        }
                        else{ //Not acked, but not expired, so keep it in queue.
                            call timeQueue.enqueue(ts);
                        }
                    }
                    else{ //The byte has been acked. No need to keep the timestamp.
                        // dbg(TRANSPORT_CHANNEL, "INFO (timeout): Data (byte: %d) ACKED. | LA: %d | NTS: %d\n", ts.byte, socket.lastAcked, socket.nextToSend);
                    }
                }
            }
        }
        //Restart the timer for timeouts.
        timeoutTime = (call timeQueue.empty()) ? 2000 : ((call timeQueue.head()).expiration - call timeoutTimer.getNow());
        call timeoutTimer.startOneShot(timeoutTime);
    }
    
    /* == closeSocket ==
        Begins the teardown procedure by sending a FIN and updating state. 
        Called when the "clostConnection" command is called. */
    task void closeSocket(){
        socket_store_t socket;
        socket = call sockets.get(IDtoClose);
        
        //Change socket state.
        socket.state = WAIT_ACKFIN;
        call sockets.insert(IDtoClose, socket);

        //Send a FIN request.
        sendSUTD(IDtoClose, FIN);
    }

    /* == handlePack ==
        The workhorse of this module.
        Based on a given state and flags of an inbound packet buffered in the receiveQueue, handle a packet accordingly.
        This includes setup, teardown, and also data transfer. It's a big one!
        Posted whenever a pack is received. */
    task void handlePack(){
        //If there's something in the send queue (which there should be if the task was posted)
        if(call receiveQueue.size()>0){
            //Get the incoming packet.
            tcpack incomingMsg = call receiveQueue.dequeue();
            //Grab some of the variables from the headers for ease of access later.
            uint8_t incomingFlags = (incomingMsg.flagsandsize & 224)>>5;
            uint8_t incomingSize = incomingMsg.flagsandsize & 31;
            uint8_t incomingSrcPort = ((incomingMsg.ports) & 240)>>4;
            uint8_t incomingDestPort = (incomingMsg.ports) & 15;
            uint32_t socketID = getSocketID(incomingMsg.src, incomingSrcPort, incomingDestPort);
            
            //If the socket this packet is trying to reach already exists,
            if(call sockets.contains(socketID)){
                //Get the requested socket for later.
                socket_store_t socket = call sockets.get(socketID);

                //Check to ensure the requested byte falls within a valid range (not a resend, and RIGHT NOW NOT HOLES EITHER)
                if((byteCount_t)(socket.nextExpected - incomingMsg.currbyte) > SOCKET_BUFFER_SIZE && socket.state == CONNECTED){
                    dbg(TRANSPORT_CHANNEL, "Unexpected Byte Order: Expected byte %d, got byte %d. Dropping Packet.\n",socket.nextExpected, incomingMsg.currbyte);
                    return;
                }

                //Otherwise, check which flags the packet has to handle it accordingly.
                switch(incomingFlags){
                    //SYNC: 0 | ACK: 0 | FIN: 0 (DATA)
                    case(EMPTY): //Expected states: CONNECTED, for data transfer.
                        //If connected, then empty flag field implies packet contains data.
                        if(socket.state==CONNECTED){
                            //If room in buffer for the payload data (no holes),
                            if(((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE >= incomingSize || socket.nextToRead==socket.nextExpected){
                                tcpack acker;
                                //If expecting the byte, copy into memory.
                                //Does not allow for holes or out of order sequence numbers.
                                if(incomingMsg.currbyte==socket.nextExpected){
                                    //If copying into the buffer does not require a wraparound, then directly copy.
                                    if(socket.nextExpected%SOCKET_BUFFER_SIZE+incomingSize<SOCKET_BUFFER_SIZE){
                                        memcpy(&(socket.recvBuff[socket.nextExpected%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize);
                                        dbg(TRANSPORT_CHANNEL, "INFO (buffer): Copied bytes. Buffer:\n");
                                        printBuffer(socket.recvBuff, SOCKET_BUFFER_SIZE);
                                    }
                                    else{//Copying requires a buffer wraparound
                                        //Calculate the remaining bytes that do not fit in the remaining buffer before wrap.
                                        uint8_t overflow = socket.nextExpected%SOCKET_BUFFER_SIZE+incomingSize-SOCKET_BUFFER_SIZE;
                                        // dbg(TRANSPORT_CHANNEL,"Looping Buffer, NE: %d, size: %d, overflow %d\n",socket.nextExpected,incomingSize,overflow);

                                        //Copy the bytes according to the wraparound.
                                        memcpy(&(socket.recvBuff[socket.nextExpected%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize-overflow);
                                        memcpy(&(socket.recvBuff[0]),incomingMsg.data+incomingSize-overflow,overflow);
                                        
                                        //Print the buffer.
                                        dbg(TRANSPORT_CHANNEL, "INFO (buffer): Copied bytes. Buffer:\n");
                                        printBuffer(socket.recvBuff, SOCKET_BUFFER_SIZE);
                                    }

                                    //Update socket values.
                                    //breaks with holes or sliding window.
                                    socket.lastRecv = incomingMsg.currbyte+incomingSize;
                                    socket.nextExpected+=incomingSize;
                                }
                                else{ //If older bytes (already know it isn't newer stuff cause not accepting holes)
                                    dbg(TRANSPORT_CHANNEL,"Duplicate Data from byte %d\n",incomingMsg.currbyte);
                                }

                                //Update the socket.
                                call sockets.insert(socketID,socket);

                                //Send an ACK for the data.
                                makeTCPack(&acker,0,1,0,0,socketID,
                                    (socket.nextToRead-socket.nextExpected)%SOCKET_BUFFER_SIZE, //advertised window; negative mod may be problem
                                    noData());
                                call send.send(255,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&acker);
                                dbg(TRANSPORT_CHANNEL,"INFO (transport): Got Bytes [%d, %d). Expecting Byte %d\n",incomingMsg.currbyte%SOCKET_BUFFER_SIZE,(incomingMsg.currbyte+incomingSize)%SOCKET_BUFFER_SIZE,socket.nextExpected%SOCKET_BUFFER_SIZE);
                                
                                //Tell the application that data is ready to receive.
                                signal TinyController.gotData(socketID,socket.nextExpected-socket.nextToRead);//signal how much contiguous data is ready
                            }
                            else{ //No room in buffer. Drop packet.
                                dbg(TRANSPORT_CHANNEL,"No room in recvBuffer. nextToRead: %d, currbyte: %d, room: %d, IS: %d\n",socket.nextToRead,socket.nextExpected,(SOCKET_BUFFER_SIZE+socket.nextToRead - socket.nextExpected)%SOCKET_BUFFER_SIZE,incomingSize);
                            }
                        }
                        else{ //Unexpected state (not connected).
                            dbg(TRANSPORT_CHANNEL, "ERROR: EMPTY, state = %s\n", getPrinted(socket.state, TRUE));
                        }
                        break;
                    //SYNC: 1 | ACK: 0 | FIN: 0
                    case(SYNC): //Expected states: No socket. Implies crash or otherwise.
                        dbg(TRANSPORT_CHANNEL, "ERROR: SYNC, state = %s\n", getPrinted(socket.state, TRUE));
                        break;
                    //SYNC: 0 | ACK: 1 | FIN: 0
                    case(ACK): //Expected states: SYNC_RCVD, CONNECTED, CLOSED, WAIT_ACKFIN, WAIT_ACK
                        switch(socket.state){
                            //If SYNC_RCVD, then SYNC_ACK has been ACKed. Move to connected and prepare for data.
                            case(SYNC_RCVD):
                                //Update socket state.
                                socket.state = CONNECTED;
                                socket.nextExpected++;
                                socket.nextToWrite = socket.nextToSend;
                                socket.nextToRead = socket.nextExpected;
                                call sockets.insert(socketID, socket);
                            dbg(TRANSPORT_CHANNEL,"INFO (transport): Socket %d CONNECTED, nextExpected: %d\n",socketID, socket.nextExpected%SOCKET_BUFFER_SIZE);

                                //Signal that data is inbound.
                                signal TinyController.connected(socketID);
                                break;
                            //If connected, then could be ACKing data. Must update window.
                            case(CONNECTED):
                                // dbg(TRANSPORT_CHANNEL,"Got Ack. %d is expecting byte %d. My next byte is %d. Last Acked: %d\n",incomingMsg.src,incomingMsg.nextbyte,socket.nextToSend, socket.lastAcked);
                                
                                //Previous wraparound code. Analyze if needed.
                                // if(((byteCount_t)(socket.nextToSend-socket.lastAcked)<SOCKET_BUFFER_SIZE && (byteCount_t)(incomingMsg.nextbyte-socket.lastAcked)<SOCKET_BUFFER_SIZE) //no wrap
                                // || ((byteCount_t)(socket.nextToSend-socket.lastAcked)>SOCKET_BUFFER_SIZE && (byteCount_t)(incomingMsg.nextbyte-socket.lastAcked)>SOCKET_BUFFER_SIZE)){//wrap
                                
                                //If the ACK is acking previously unACKed data, update the socket.
                                if((byteCount_t)(incomingMsg.nextbyte - socket.lastAcked) < SOCKET_BUFFER_SIZE){//if acking more stuff
                                    //Update the socket.
                                    socket.lastAcked = incomingMsg.nextbyte;
                                    call sockets.insert(socketID, socket);

                                    //STOP&WAIT: Enqueue more data only if we updated our lastAcked (meaning the packet is out of flight).
                                    //If we have more data to send, and there isn't data in flight, then send the next piece!
                                    if(socket.nextToWrite!=socket.nextToSend && !isByteinFlight(socketID,incomingMsg.nextbyte)){
                                        //Queue the data to send.
                                        call sendQueue.enqueue(socketID);
                                        post sendData();
                                    }
                                }
                                else{ //Ack is for previous data.
                                    dbg(TRANSPORT_CHANNEL,"Node %d Expecting %d. Already acked up to %d.\n", incomingMsg.src, incomingMsg.nextbyte, socket.lastAcked);
                                }
                                break;
                            
                            //If the other host does not receive our ACK, then they will not close. This is a problem, because this socket is removed.
                            //  Must change such that the client responds only with an ACK if both FIN and ACK are received.
                            //If we've closed and responded to their FIN with an ACK, then the ACK gives us permission to close.
                            case(CLOSED):
                                //Remove the socket.
                                call sockets.remove(socketID);
                                dbg(TRANSPORT_CHANNEL, "INFO (socket): Removing socket %d. %d remaining sockets.\n",socketID,call sockets.size());
                                break;
                            //If waiting for an ACK and a FIN before closing, update to only wait for a FIN.
                            case(WAIT_ACKFIN): 
                                //Update socket state.
                                socket.state = WAIT_FIN;
                                socket.nextExpected++;
                                call sockets.insert(socketID, socket);
                                break;
                            //Static memory "IDtoClose" causes issues. Implement a queue.
                            //If only waiting for an ACK, begin socket removal process.
                            //Change this such that it sends an ACK now that it has seen both a FIN and ACK.
                            case(WAIT_ACK):
                                //Update socket state.
                                socket.state = WAIT_FINAL;
                                socket.nextExpected++;
                                call sockets.insert(socketID, socket);

                                //Now, send an ACK.
                                sendSUTD(socketID, ACK);

                                IDtoClose = socketID;
                                call removeDelay.startOneShot(2*socket.RTT);
                                break;
                            //Unexpected state, therefore unknown behavior. Drop packet.
                            default:
                                dbg(TRANSPORT_CHANNEL, "ERROR: ACK, state = %s\n",getPrinted(socket.state, TRUE));
                                break;
                        }
                        break;
                    //SYNC: 0 | ACK: 0 | FIN: 1
                    case(FIN): //Expected states: CONNECTED, WAIT_ACKFIN, or WAIT_FIN. Otherwise, unknown behavior.
                        //Based on state of a packet, respond to FIN.
                        //No matter what, an ACK will be sent after updating state.
                        switch(socket.state){
                            //If connected, tell app to close and respond via an ack.
                            //For now, this "signal" is done by a dummy timer that responds after a certain period of time to represent the app has closed.
                            case(CONNECTED):
                                IDtoClose = socketID;
                                socket.state = CLOSING;

                                call closeDelay.startOneShot(socket.RTT);
                                break;
                            //If waiting for an ACK and a FIN before closing, update to only wait for an ACK.
                            case(WAIT_ACKFIN):
                                socket.state = WAIT_ACK;
                                return; //Prevents sending an ACK until FIN is received.
                            //Static memory "IDtoClose" causes issues. Implement a queue.
                            //If waiting only for FIN, begin socket removal process.
                            case(WAIT_FIN):
                                socket.state = WAIT_FINAL;

                                IDtoClose = socketID;
                                call removeDelay.startOneShot(2*socket.RTT);
                                break;
                            //Unexpected state, therefore unknown behavior. Drop packet by returning.
                            default:
                                dbg(TRANSPORT_CHANNEL, "ERROR: FIN, state = %s\n", getPrinted(socket.state, TRUE));
                                return;
                        }
                        //Update the last Acked byte.
                        socket.lastAcked = incomingMsg.nextbyte;
                        
                        //Update the socket's expected sequence.
                        socket.nextExpected++;
                        call sockets.insert(socketID, socket);

                        //Send the ACK.
                        sendSUTD(socketID, ACK);
                        break;
                    //SYNC: 1 | ACK: 1 | FIN: 0
                    case(SYNC_ACK): //Expect to be in SYNC_SENT state, otherwise unknown behavior.
                        //Response for our SYNC, update and respond with ACK
                        if(socket.state == SYNC_SENT){

                            //Update socket state. Previously unknown seq can be established.
                            socket.state = CONNECTED;
                            socket.nextExpected = incomingMsg.currbyte+1;
                            call sockets.insert(socketID, socket);
                            dbg(TRANSPORT_CHANNEL,"INFO (transport): Socket %d CONNECTED, nextExpected: %d\n",socketID, socket.nextExpected%SOCKET_BUFFER_SIZE);

                            //Respond with an ACK.
                            sendSUTD(socketID, ACK);

                            //Prepare to send data.
                            call sendDelay.startOneShot(socket.RTT);
                        }
                        else{ //unknown behavior
                            dbg(TRANSPORT_CHANNEL, "ERROR: SYNC_ACK, state = %s\n", getPrinted(socket.state, TRUE));
                        }
                        break;
                    //SYNC: 0 | ACK: 1 | FIN: 1
                    case(ACK_FIN): //Unimplemented as of now, instantaneous app close not possible.
                        dbg(TRANSPORT_CHANNEL, "ACK_FIN received.\n");
                        break;
                    //Unknown Case.
                    default:
                        dbg(TRANSPORT_CHANNEL, "ERROR: unknown flag combo: %d. Dropping.\n", incomingFlags);
                        break;
                }
            }
            else{ //No socket
                if(incomingFlags == SYNC && call ports.contains(incomingDestPort)){
                    socket_store_t newSocket;

                    createSocket(&newSocket, SYNC_RCVD, incomingDestPort, incomingSrcPort, incomingMsg.src, incomingMsg.currbyte);

                    //Respond with a SYNC_ACK.
                    sendSUTD(socketID, SYNC_ACK);

                    dbg(TRANSPORT_CHANNEL, "INFO (socket): New Socket.\n");
                    printSocket(socketID);
                }
                else{
                    dbg(TRANSPORT_CHANNEL, "Nonsense flags %s OR Empty Port: %d. Dropping.\n",getPrinted(incomingFlags, FALSE),incomingDestPort);
                }
            }
            if(call receiveQueue.size()>0){
                post handlePack();
            }
        }
    }  

    /* == getPort ==
        Called when an application wishes to lease a port. Requires a request and the protocol of the application.
        Arguments:
            portRequest: an integer value representing the port the application requests.
            ptcl: the protocol of the leasing application.
        Function:
            If possible, allocated a port to a given protocol.
            Does so by hashing the given ptcl with a key of the portRequest in the 'ports' hashmap.
        Returns FAIL if the port identified by the portRequest is already in use; SUCCESS otherwise. */
    command error_t TinyController.getPort(uint8_t portRequest, socket_t ptcl){
        if(call ports.contains(portRequest)){
            dbg(TRANSPORT_CHANNEL, "ERROR: Port %d is stupid. You're screwed. Port %d doesn't care.\n",portRequest, call ports.get(portRequest));
            return FAIL;
        }
        else{
            call ports.insert((uint32_t)portRequest, ptcl);
            dbg(TRANSPORT_CHANNEL, "PTL %d on Port %d\n",ptcl, portRequest);
            return SUCCESS;
        }
    }

    /* == requestConnection ==
        Called when an application wishes to connect to another application on a known destination address and port.
        Arguments:
            dest: The ID or address of the host the application wishes to connect with.
            destPort: The port number the application wishes to connect to on the destination device.
            srcPort: The port of the application, used to set up a socket for the port the application is using.
        Function:
            If possible, creates a new socket in the SYNC_SENT state using the default params given. Note the lack of an acknowledged sequence number (we can't know it yet!)
            If possible, sends a SYNC packet to the destination port via routing.
            Finally, adds the new socket to the 'sockets' hash using the socketID as a key (where socketID is a combination of the 4-tuple dest/src, dest/srcPort).
        Returns FAIL if the application does not have a leased port, SUCCESS if otherwise.
        Note: There are more checks to do here - does this app have the right to request on this srcPort? Does the destPort exist? Etc. */
    command uint32_t TinyController.requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        socket_store_t newSocket;
        uint32_t socketID;

        if(!call ports.contains(srcPort)){
            dbg(TRANSPORT_CHANNEL, "ERROR: cannot make socket with port %d (unused).\n",srcPort);
            return 0;
        }
        socketID = getSocketID(dest, destPort, srcPort);
        if(call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL,"ERROR: socket %d already exists\n",socketID);
            return 0;
        }

        createSocket(&newSocket, SYNC_SENT, srcPort, destPort, dest, 0);

        sendSUTD(socketID, SYNC);
        
        dbg(TRANSPORT_CHANNEL, "INFO (socket): New Socket.\n");
        printSocket(socketID);
        return socketID;
    }
    
    /* == closeConnection ==
        Called when an application wishes to close a connection (and destroy the sockets) between itself and another node.
        Arguments:
            dest: The ID of the destination host to end the connection of.
            destPort: The port of the destination host the connection is using via a socket.
            srcPort: The port the current application is using, to identify the socket to destroy.
        Function:
            If possible, changes the state of the socket to WAIT_ACKFIN, and sends a FIN pack to the destination port via routing.
        Returns FAIL if the socket described by the above params does not exist, SUCCESS otherwise. */
    command error_t TinyController.closeConnection(uint32_t socketID){
        
        if(!call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL, "ERROR: Cannot close socket ID %d (DNE).\n",socketID);
            return FAIL;
        }

        IDtoClose = socketID;
        post closeSocket();

        return SUCCESS;
    }

    /* == write ==
        Writes a given payload to a socket's sendBuffer, after checking for certain edge cases.
        (Does the socket exist, is there room in the buffer to write this, etc.)
        Called when an application with an existing connection has permission to write to a socket and wishes to do so. */
    command error_t TinyController.write(uint32_t socketID, uint8_t* payload, uint8_t length){
        socket_store_t socket;
        //Check to see if the socket exists
        if(call sockets.contains(socketID)){
            //If it does, retrieve it for later use.
            socket = call sockets.get(socketID);
            //If the socket is connected and ready to send data,
            if(socket.state == CONNECTED){
                //If there is room in the buffer to write the whole payload to (or the buffer is empty), then it is possible to write.
                if(((byteCount_t)(socket.lastAcked-socket.nextToWrite))%SOCKET_BUFFER_SIZE>=length || socket.lastAcked==socket.nextToWrite){
                    //If the memory written to does not include a wraparound, write directly.
                    if(socket.nextToWrite%SOCKET_BUFFER_SIZE+length<SOCKET_BUFFER_SIZE){
                        memcpy(&(socket.sendBuff[socket.nextToWrite%SOCKET_BUFFER_SIZE]),payload,length);

                        //Print the result of writing.
                        dbg(TRANSPORT_CHANNEL, "INFO (buffer): Wrote bytes. Buffer:\n");
                        printBuffer(socket.sendBuff, SOCKET_BUFFER_SIZE);
                    }
                    else{//Writing requires a wraparound
                        //Consider the excess bytes that must be wrapped back to the beginning, then write at the end and start.
                        uint8_t overflow = socket.nextToWrite%SOCKET_BUFFER_SIZE+length-SOCKET_BUFFER_SIZE;
                        memcpy(&(socket.sendBuff[socket.nextToWrite%SOCKET_BUFFER_SIZE]),payload,length-overflow);
                        memcpy(&(socket.sendBuff[0]),payload+length-overflow,overflow);
                    }
                    //Update the socket pointers with this new information.
                    socket.nextToWrite+=length;
                    call sockets.insert(socketID,socket);

                    //Enqueue this new data for sending.
                    call sendQueue.enqueue(socketID);
                    post sendData();

                    //Print the result of writing.
                    dbg(TRANSPORT_CHANNEL, "INFO (buffer): Wrote bytes. Buffer:\n");
                    printBuffer(socket.sendBuff, SOCKET_BUFFER_SIZE);

                    return SUCCESS;
                }
                else{ //Not enough room in the current buffer to write the payload to.
                    dbg(TRANSPORT_CHANNEL,"ERROR: Not enough room in sendBuffer. INFO: lastAcked: %d | nextToWrite: %d | room: %d | length: %d\n",socket.lastAcked,socket.nextToWrite,((byteCount_t)(socket.lastAcked-socket.nextToWrite))%SOCKET_BUFFER_SIZE,length);
                    return FAIL;
                }
            }
            else{ //Socket is not connected, and therefore cannot send.
                dbg(TRANSPORT_CHANNEL,"ERROR: Socket %d not connected.\n",socketID,socket.state);
                return FAIL;
            }
        }
        else{ //Socket was not found under the given socketID
            dbg(TRANSPORT_CHANNEL,"ERROR: No Socket %d.\n",socketID);
            return FAIL;
        }

    }

    /* == read ==
        Copies a given amount of data from the recvBuffer of a given socket to another location in memory for an application to read.
        Must check several things, including if the read data wraps around the buffer, etc.
        Called when an application with a preexisting connection wants to read from its socket.*/
    command error_t TinyController.read(uint32_t socketID, uint8_t length, uint8_t* location){
        //Check that the socket exists.
        if(call sockets.contains(socketID)){
            //If the socket exists, store it for later use.
            socket_store_t readSocket = call sockets.get(socketID);

            //Print the currently stored data.
            dbg(TRANSPORT_CHANNEL, "INFO (buffer): Reading bytes. Buffer:\n");
            printBuffer(readSocket.recvBuff, SOCKET_BUFFER_SIZE);

            //If the portion of memory to be read does not require a wraparound in the recbBuffer of the socket, copy directly.
            if(readSocket.nextToRead%SOCKET_BUFFER_SIZE+length<SOCKET_BUFFER_SIZE){
                memcpy(location,&(readSocket.recvBuff[readSocket.nextToRead%SOCKET_BUFFER_SIZE]),length);
            }
            else{//Otherwise, a wraparound is required
                //Consider the excess bytes that are stored at the beginning, then write the end and start to the destination memory location.
                uint8_t overflow = readSocket.nextToRead%SOCKET_BUFFER_SIZE+length-SOCKET_BUFFER_SIZE;
                memcpy(location,&(readSocket.recvBuff[readSocket.nextToRead%SOCKET_BUFFER_SIZE]),length-overflow);
                memcpy(location+length-overflow,&(readSocket.recvBuff[0]),overflow);
            }
            //Update the socket's pointers to reflect this read action.
            readSocket.nextToRead+=length;
            call sockets.insert(socketID,readSocket);
            return SUCCESS;
        }
        else{ //Socket does not exist.
            dbg(TRANSPORT_CHANNEL,"ERROR: No Socket %d.\n",socketID);
            return FAIL;
        }
    }

    /* == gotTCP ==
        Signaled when Waysender receives a packet marked with a TCP protocol.
        Copies the pack into memory and queues it for handling. */
    event void send.gotTCP(uint8_t* pkt){
        //Copy the incoming packet into memory.
        memcpy(&storedMsg, (tcpack*)pkt, tc_pkt_len);
        //Post the handling task.
        call receiveQueue.enqueue(storedMsg);
        post handlePack();
    }

    /* == timeoutTimer.fired ==
        Called when the timeoutTimer expires.
        This timer is used to check for timeouts of in-flight packets.
        It does this by posting the checkTimeouts task, which recursively calls this timer. */
    event void timeoutTimer.fired(){
        post checkTimeouts();
    }

    /* == closeDelay.fired ==
        Called when the closeDelay timer is fired.
        This timer is a dummy timer, used to represent an application signaling that it is finished with a connection.
        It is called right now upon receiving a FIN packet when in the CONNECTED state. */
    event void closeDelay.fired(){
        //Get the ID of the socket to close. This should be done on a queue of IDtoCloses, not just a static one.
        socket_store_t socket = call sockets.get(IDtoClose);
        socket.state = CLOSED;
        call sockets.insert(IDtoClose, socket);

        //Create and send a FIN message to the other end of the connection.
        sendSUTD(IDtoClose, FIN);
    }

    /* == sendDelay.fired ==
        called when the sendDelay timer is fired.
        This timer represents the delay necessary after sending an ACK to a SYNC_ACK before sending data.
        Once this timer fires, variables are updated and a signal that the socket is ready is sent to all applications.
        This obviously has security concerns. */
    event void sendDelay.fired(){
        //As of right now, only the first socket sends data for a given simulation. 
        //A queue for sockets to signal they are ready to send must be implemented.
        uint32_t socketID = call sockets.getIndex(0);

        //Get and update the socket so it is ready to send data.
        socket_store_t socket = call sockets.get(socketID);
        socket.nextToWrite = socket.nextToSend;
        socket.nextToRead = socket.nextExpected;
        call sockets.insert(socketID,socket);

        //Signal the connection is ready to use.
        signal TinyController.connected(socketID);
        
        dbg(TRANSPORT_CHANNEL, "INFO (transport): Socket %d RTS.\n",socketID);
    }

    /* == removeDelay.fired ==
        Called when the removeDelay timer fires.
        This timer is called when a client connection enters a WAIT_FINAL state.
        After this timer fires, the connection is assumed to be mutually closed, and the socket is removed from the client. */
    event void removeDelay.fired(){
        //As of right now, this is done via a static "IDtoClose" variable. This should be changed to a queue of sockets to close.
        call sockets.remove(IDtoClose);
        dbg(TRANSPORT_CHANNEL, "INFO (socket): Removing socket %d. %d remaining sockets.\n", IDtoClose, call sockets.size());
    }

    /* == createSocket ==
        Called when socket creation is necessary, and a socket does not already exist.
        Initializes and adds a socket to the sockets hash with given parameters.
        Note: buffers are initialized to all '*' characters. */
    void createSocket(socket_store_t* socket, uint8_t state, socket_port_t srcPort, socket_port_t destPort, uint8_t dest, uint8_t theirByte){
        //Create the socket.
        socket_addr_t newDest;

        //Fill out the destination.
        newDest.port = destPort;
        newDest.addr = dest;
        
        //Unused socket "flag" parameter.
        // socket->flag = flag;

        //Fill out the state, source and destination.
        socket->state = state;
        socket->srcPort = srcPort;
        socket->dest = newDest;

        //Fill out the sending portion of the socket.
        memset(socket->sendBuff,(uint8_t)'_',SOCKET_BUFFER_SIZE);
        socket->nextToWrite = call Random.rand16();//Randomize sequence number 0, 255
        socket->lastAcked = socket->nextToWrite-1; //Nothing has been acknowledged because nothing's sent, it's new!
        socket->nextToSend = socket->nextToWrite; //Nothing has been sent, it's new!

        //Fill out the receiving portion of the socket.
        memset(socket->recvBuff,(uint8_t)'_',SOCKET_BUFFER_SIZE);
        socket->nextToRead = theirByte; //We may know their current byte they sent
        socket->nextExpected = theirByte+1; //The next byte will start as 1 more than their current byte!
        socket->lastRecv = theirByte; //This is the first time we've gotten something, let it have ID 0.

        //Arbitrary RTT, should be dynamic.
        socket->RTT = 2000;

        //Insert this new socket into the hash.
        call sockets.insert(getSocketID(dest,destPort,srcPort),*socket); 
    }

    /* == makeTCPack ==
        Yet another makePack function, adding TC headers to a given payload.
        sync, ack, and fin are all 1 or 0, representing the flags.
        size is the payload size.
        socketID gives the pack information about the socket.
        adWindow is the advertised window field of a node's recvBuffer.
        byteIndex is the byte that */
    void makeTCPack(tcpack* pkt, uint8_t sync, uint8_t ack, uint8_t fin, uint8_t size, uint32_t socketID, uint8_t adWindow, uint8_t byteIndex){

        //Get the socket, and initialize the fields that go in the "flagsandsize" and "ports" fields of a TCPack.
        // memset(pkt,0,tc_pkt_len);
        uint8_t flagField = 0;
        uint8_t portField = 0;
        socket_store_t socket = call sockets.get(socketID);
        if(!call sockets.contains(socketID)) dbg(TRANSPORT_CHANNEL,"WARNING: Makepack cannot find socket %d.\n",socketID);

        //Fill out the flags and size field.
        //(left->right): 0000 0000
        //SYNC,ACK,FIN,size[5]
        flagField += sync<<7;
        flagField += ack<<6;
        flagField += fin<<5;
        flagField += (size & 31);
        pkt->flagsandsize = flagField;
        
        //Fill out the destination and source information.
        //(left->right): 0000 0000
        //destPort, srcPort
        portField += socket.dest.port<<4;
        portField += (socket.srcPort & 15);
        pkt->ports = portField;
        pkt->src = TOS_NODE_ID;
        pkt->dest = socket.dest.addr;

        //Fill out relevant buffer information.
        pkt->currbyte = socket.nextToSend;
        pkt->nextbyte = socket.nextExpected;
        pkt->adWindow = adWindow;
     
        //Copy the payload into the packet.
        memset(pkt->data,0,tc_max_pld_len);
        //If there is data to send (size == 0 implies no data to send),
        if(size>0){
            //If the memory to be copied into the payload does not require a wraparound, copy directly into the payload.
            if(byteIndex%SOCKET_BUFFER_SIZE+size<SOCKET_BUFFER_SIZE){
                memcpy(pkt->data, &(socket.sendBuff[byteIndex%SOCKET_BUFFER_SIZE]), size);
            }
            else{ //Otherwise, a wraparound is required
                //Consider the excess bytes that are stored at the beginning, then write the end and start into the payload.
                uint8_t overflow = byteIndex%SOCKET_BUFFER_SIZE+size-SOCKET_BUFFER_SIZE;
                memcpy(pkt->data,&(socket.sendBuff[byteIndex%SOCKET_BUFFER_SIZE]),size-overflow);
                memcpy(pkt->data+size-overflow,&(socket.sendBuff[0]),overflow);
            }
        } 
    }

    /* == printSocket ==
        Debugging function to print the state of a socket, given a socketID. */
    void printSocket(uint32_t socketID){
        if(!call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL, "ERROR: No socket with ID %d exists.\n",socketID);
        }
        else{
            socket_store_t printedSocket = call sockets.get(socketID);
            char* printedState = getPrinted(printedSocket.state, TRUE);
            //This translated given state codes into the names of each code.
            switch(printedSocket.state){
                case(LISTEN):
                    printedState = "LISTEN";
                    break;
                case(CONNECTED):
                    printedState = "CONNECTED";
                    break;
                case(SYNC_SENT):
                    printedState = "SYNC_SENT";
                    break;
                case(SYNC_RCVD):
                    printedState = "SYNC_RCVD";
                    break;
                case(WAIT_ACKFIN):
                    printedState = "WAIT_ACKFIN";
                    break;
                case(WAIT_FIN):
                    printedState = "WAIT_FIN";
                    break;
                case(WAIT_ACK):
                    printedState = "WAIT_ACK";
                    break;
                case(WAIT_FINAL):
                    printedState = "WAIT_FINAL";
                    break;
                case(CLOSED):
                    printedState = "CLOSED";
                    break;
                case(CLOSING):
                    printedState = "CLOSING";
                    break;
                default:
                    dbg(TRANSPORT_CHANNEL, "Unknown state.\n");
            }
            dbg(TRANSPORT_CHANNEL, "INFO (socket): ID: %d | State: %s | srcPort: %d | destPort: %d | src: %d | dest: %d\n",
                socketID,
                printedState,
                printedSocket.srcPort,
                printedSocket.dest.port,
                TOS_NODE_ID,
                printedSocket.dest.addr
            );
        }
    }

    /* == printTimeStamp ==
        Debug function to print a socket, given a pointer to the timestamp. */
    void printTimeStamp(timestamp* ts){
        dbg(TRANSPORT_CHANNEL,"INFO (timestamp): Current: %d | Expiration: %d | ID: %d | Byte: %d | intent: %s\n", call timeoutTimer.getNow(), ts->expiration, ts->id, ts->byte, getPrinted(ts->intent, FALSE));
    }

    /* == getSocketID ==
        Returns a unique socket ID for a given 4-tuple of (destination ID, destination port, source ID, source port). */
    uint32_t getSocketID(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        return (srcPort<<24) + (destPort<<16) + (TOS_NODE_ID<<8) + dest;
    }

    /* == getSID ==
        Same as getSocketID, but takes a tcPack instead of the 4-tuple. */
    uint32_t getSID(tcpack msg){
        //Get information needed to retrieve the socket ID.
        uint8_t incomingSrcPort = (msg.ports & 240)>>4;
        uint8_t incomingDestPort = (msg.ports) & 15;
        
        //Return the ID using getSocketID.
        return getSocketID(msg.src, incomingSrcPort, incomingDestPort);        
    }

    /* == makeTimeStamp ==
        "Makepack" for a timestamp struct. */
    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID, uint8_t byte, uint8_t intent){
        ts->expiration = call timeoutTimer.getNow()+timeout;
        ts->id = socketID;
        ts->byte = byte;
        ts->intent = intent;
    }

    /* == isByteinFlight ==
        Function to determine if a given byte is in flight or not.
        Does so by checking if there exists a timestamp for a given byte for a socket. */
    bool isByteinFlight(uint32_t socketID, byteCount_t byte){
        int i=0;
        uint32_t numInFlight = call timeQueue.size();
        timestamp ts;
        //Check every timestamp for the given byte.
        for(i=0;i<numInFlight;i++){
            ts = call timeQueue.element(i);
            //If the byte of the timestamp is the one in question, return TRUE.
            if(ts.id==socketID && ts.byte == byte){
                return TRUE;
            }
        }
        //Otherwise, return FALSE.
        return FALSE;
    }

    /* == noData ==
        Code readability function, returns a null pointer. */
    uint8_t noData(){
        return 0;
    }

    /* == sendSUTD ==
        Called when a setup/teardown (SUTD) packet needs to be sent.
        Sends the packet with a given intent along a given socket connection. */
    void sendSUTD(uint32_t socketID, uint8_t intent){
        socket_store_t socket = call sockets.get(socketID);
        tcpack sutdPack;
        timestamp ts;

        //Make the packet according to intent, and send it.
        switch(intent){
            case(EMPTY):
                dbg(TRANSPORT_CHANNEL, "ERROR: No intent for SUTD.\n");
                break;
            case(FIN):
                makeTCPack(&sutdPack, 0, 0, 1, 0, socketID, 1, noData());
                break;
            case(ACK):
                makeTCPack(&sutdPack, 0, 1, 0, 0, socketID, 1, noData());
                break;
            case(ACK_FIN):
                makeTCPack(&sutdPack, 0, 1, 1, 0, socketID, 1, noData());
                break;
            case(SYNC):
                makeTCPack(&sutdPack, 1, 0, 0, 0, socketID, 1, noData());
                break;
            case(SYNC_FIN):
                makeTCPack(&sutdPack, 1, 0, 1, 0, socketID, 1, noData());
                break;
            case(SYNC_ACK):
                makeTCPack(&sutdPack, 1, 1, 0, 0, socketID, 1, noData());
                break;
            case(SYNC_ACK_FIN):
                makeTCPack(&sutdPack, 1, 1, 1, 0, socketID, 1, noData());
                break;
            default:
                dbg(TRANSPORT_CHANNEL, "ERROR: Unknown intent: %d.\n",intent);
                break;
        }
        call send.send(255, socket.dest.addr, PROTOCOL_TCP, (uint8_t*) &sutdPack); 

        //Update the socket's sequence to reflect this information.
        socket.nextToSend++;
        call sockets.insert(socketID, socket);

        //Add a timestamp for retransmission.
        makeTimeStamp(&ts, 2*socket.RTT, socketID, socket.nextToSend, intent);
        call timeQueue.enqueue(ts);
        if(!call timeoutTimer.isRunning()){ 
            timeoutTime = (call timeQueue.empty()) ? 2000 : ((call timeQueue.head()).expiration - call timeoutTimer.getNow());
            call timeoutTimer.startOneShot(timeoutTime); 
        }
    }

    /* == needsRetransmit ==
        Called when determining if a SUTD timestamp needs retransmission is necessary.
        Based on the current state of the timestamp's socket,
        It can be deduced whether retransmission is necessary. */
    bool needsRetransmit(timestamp ts){
        socket_store_t socket = call sockets.get(ts.id);
        //Checks if a given timestamp for SUTD needs retransmission.
        switch(ts.intent){
            case(EMPTY):
                dbg(TRANSPORT_CHANNEL, "ERROR: No intent for SUTD.\n");
                break;
            case(FIN):
                if(socket.state == WAIT_ACKFIN || socket.state == CLOSED){ 
                    dbg(TRANSPORT_CHANNEL, "WARNING (timeout): FIN unfulfilled (state: %s).\n", getPrinted(socket.state, TRUE));
                    return TRUE; }
                break;
            case(ACK):
                //Don't need to retransmit on setup. 
                //Retransmission of SYNC_ACK will cause another ACK.

                //Don't need to retransmit on teardown.
                //Retransmission of FIN will cause another ACK.
                break;
            case(ACK_FIN):
                //ACK_FIN unimplemented as of now
                break;
            case(SYNC):
                if(socket.state == SYNC_SENT){ 
                    dbg(TRANSPORT_CHANNEL, "WARNING (timeout): SYNC unfulfilled (state: %s).\n", getPrinted(socket.state, TRUE));
                    return TRUE; }
                break;
            case(SYNC_FIN):
                //SYNC_FIN unimplemented as of now
                break;
            case(SYNC_ACK):
                if(socket.state == SYNC_RCVD){ 
                    dbg(TRANSPORT_CHANNEL, "WARNING (timeout): SYNC_ACK unfulfilled (state: %s).\n", getPrinted(socket.state, TRUE));
                    return TRUE; }
                break;
            case(SYNC_ACK_FIN):
                //SYNC_ACK_FIN unimplemented as of now
                break;
            default:
                dbg(TRANSPORT_CHANNEL, "ERROR: Unknown intent: %d.\n", getPrinted(ts.intent, FALSE));
                break;
        }
        // dbg(TRANSPORT_CHANNEL, "INFO (timeout): %s fulfilled (state: %s).\n", getPrinted(ts.intent, FALSE), getPrinted(socket.state, TRUE));
        return FALSE;
    }

    /* == getPrinted ==
        Returns the printed value of an enumerated state or intent. */
    char* getPrinted(uint8_t value, bool isState){
        if(isState){
            switch(value){
                case(LISTEN): return "LISTEN";
                case(CONNECTED): return "CONNECTED";
                case(SYNC_SENT): return "SYNC_SENT";
                case(SYNC_RCVD): return "SYNC_RCVD";
                case(WAIT_ACKFIN): return "WAIT_ACKFIN";
                case(WAIT_FIN): return "WAIT_FIN";
                case(WAIT_ACK): return "WAIT_ACK";
                case(WAIT_FINAL): return "WAIT_FINAL";
                case(CLOSED): return "CLOSED";
                case(CLOSING): return "CLOSING";
                default: return "NULL";
            }
        }
        else{ //Is Intent
            switch(value){
                case(EMPTY): return "EMPTY";
                case(SYNC): return "SYNC";
                case(ACK): return "ACK";
                case(FIN): return "FIN";
                case(SYNC_ACK): return "SYNC_ACK";
                case(ACK_FIN): return "ACK_FIN";
                case(SYNC_FIN): return "SYNC_FIN";
                case(SYNC_ACK_FIN): return "SYNC_ACK_FIN";
                default: return "NULL";
            }
        }
    }

    /* == printBuffer ==
        Method of printing a len characters of a buffer. */
    void printBuffer(uint8_t* buffer, uint8_t len){
        uint8_t printedBuffer[len+1], i;
        memcpy(printedBuffer, buffer, len);
        printedBuffer[len]=0;
        for(i = 0; i < len; i++){
            if(printedBuffer[i] == (uint8_t)'\n'){
                printedBuffer[i] = (uint8_t)'\\';
            }
        }

        dbg(TRANSPORT_CHANNEL, "(\\=\\n) |%s|\n",printedBuffer);
        dbg(TRANSPORT_CHANNEL, "       |          |10       |20       |30       |40       |50       |60       |70       |80       |90       |100      |110      |120    |\n",printedBuffer);
    }

}
