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
    uses interface Queue<timestamp> as sendRemoveQueue; // Queue to keep track of when a socket is ready to send, or when it is ready to be removed
    uses interface Queue<uint32_t> as IDstoClose;

    uses interface Timer<TMilli> as timeoutTimer;
    uses interface Timer<TMilli> as probeTimer; //Timer to send a probe to get an updated adWindow.
    uses interface Timer<TMilli> as sendRemoveTimer; //Timer for sendRemoveQueue
    uses interface Random;
}

implementation{
    //Global Variables - not ideal, could implement a queue for these.
    tcpack storedMsg;
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
        bool probing = FALSE;

        //If a socket wants to send data..
        if(call sendQueue.size()>0){
            //Get the socket whose turn it is to send.
            socketID = call sendQueue.dequeue();
            socket = call sockets.get(socketID);

            if(socket.state!=CONNECTED){
                dbg(TRANSPORT_CHANNEL,"ERROR (sendData): Socket %d not in CONNECTED state.\n",socketID);
                call sendQueue.enqueue(socketID);
                post sendData();
                return;
            }

            if(socket.nextToSend!=socket.nextToWrite){
                timestamp ts;
                
                //Check if the data to be sent should be a probe for the adWindow.
                if(socket.theirWindow == 0){
                    socket.theirWindow = 1;
                    probing = TRUE;
                    dbg(TRANSPORT_CHANNEL, "INFO (flow): Sending window probe.\n");
                }

                //Get the amount of data to send. This is the minimum between the max payload size, the length of the data, the sending window of the socket, and the advertised window.
                length = tc_max_pld_len; //Start with the max payload size,
                if(((byteCount_t)(socket.nextToWrite-socket.nextToSend)) < length ){ length = ((byteCount_t)(socket.nextToWrite-socket.nextToSend)); } //Then check the amount to send.
                if(socket.myWindow < length){ length = socket.myWindow; } //Check the sending window,
                if(socket.theirWindow < length){ length = socket.theirWindow; } //And finally, the advertised window.
                
                //Make and send the packet.
                makeTCPack(&packet, 0, 0, 0, length, socketID, ((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE, socket.nextToSend);
                call send.send(32,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&packet);
                dbg(TRANSPORT_CHANNEL,"INFO (transportData): Sent %d bytes: [%d,%d).\n", length, socket.nextToSend%SOCKET_BUFFER_SIZE, (socket.nextToSend+length)%SOCKET_BUFFER_SIZE);

                //Add a retransmission timestamp for the packet, and call the retransmission timer if not in progress.
                makeTimeStamp(&ts, socket.RTT, socketID, socket.nextToSend, EMPTY);
                call timeQueue.enqueue(ts);
                timeoutTime = (call timeQueue.empty()) ? socket.RTT : ((call timeQueue.head()).expiration - call timeoutTimer.getNow());
                if(!call timeoutTimer.isRunning()){ call timeoutTimer.startOneShot(timeoutTime); }

                //Update the socket with the new "nextToSend" and effective window.
                socket.nextToSend+=length;
                socket.myWindow -= length;
                socket.theirWindow -= length;
                call sockets.insert(socketID,socket);

                //If data can still be sent (and there is more to send), requeue to send more.
                if(socket.myWindow > 0 && socket.theirWindow > 0 && (socket.nextToWrite != socket.nextToSend)){
                    call sendQueue.enqueue(socketID);
                    post sendData();
                    // dbg(TRANSPORT_CHANNEL, "INFO (window): Reposting; more to send. window: %d | left: %d\n", socket.myWindow, (byteCount_t)(socket.nextToWrite-socket.nextToSend));
                }
                else{
                    //If the message sent was not a probe, and there's more data but the adWindow ran out, start the probing process.
                    if(!probing && (socket.nextToWrite != socket.nextToSend) && socket.theirWindow == 0){
                        dbg(TRANSPORT_CHANNEL, "INFO (flow): Starting probing procedure.\n");
                        call probeTimer.startOneShot(10000);
                    }
                    dbg(TRANSPORT_CHANNEL, "WARNING (window): Cannot send more. mywindow: %d | theirwindow: %d | left: %d | NTW: %d | NTS: %d\n", socket.myWindow, socket.theirWindow, (byteCount_t)(socket.nextToWrite-socket.nextToSend), socket.nextToWrite, socket.nextToSend);
                }

            }
            else{ // There's no outbound data from any socket.
                dbg(TRANSPORT_CHANNEL,"WARNING (sendData): No data in sendBuffer of socket %d\n",socketID);
            }
        }
        else{
            dbg(TRANSPORT_CHANNEL,"WARNING (sendData): Nothing in sendQueue\n");
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
                    if(currentTime >= ts.expiration){
                        //Reset the sequence to what it was before.
                        socket.nextToSend--;
                        socket.lastAcked--;
                        call sockets.insert(ts.id, socket);
                        dbg(TRANSPORT_CHANNEL, "INFO (timeout): %s to %d expired. State: %s NTS: %d\n", getPrinted(ts.intent, FALSE), socket.dest.addr, getPrinted(socket.state, TRUE), socket.nextToSend);
                        sendSUTD(ts.id, ts.intent);
                    }
                    else{ //Timestamp still valid, requeue.
                        call timeQueue.enqueue(ts);
                        // dbg(TRANSPORT_CHANNEL, "INFO (timeout): %s requeued.\n", getPrinted(ts.intent, FALSE));
                    }
                }
            }
            else{ //Otherwise, is data.
                //If the distance between the last acked byte and the nextToSend byte does not wrap around the buffer,
                if(socket.lastAcked<=socket.nextToSend){
                    //Check if the first byte of the timestamped packet has NOT been acked yet.
                    if(socket.lastAcked<=ts.byte && ts.byte<socket.nextToSend){
                        //If the timestamp has timed out and hasn't been acked, retransmit the data.
                        if(currentTime>=ts.expiration){
                            dbg(TRANSPORT_CHANNEL,"INFO (timeout): Bytes [%d,...) expired. LA:%d | byte: %d | NTS: %d | Socket: %d\n", ts.byte%SOCKET_BUFFER_SIZE, socket.lastAcked, ts.byte, socket.nextToSend, ts.id);

                            //Update the socket with the setback (Go Back N style)
                            socket.myWindow += (byteCount_t)(socket.nextToSend - ts.byte);
                            socket.theirWindow += (byteCount_t)(socket.nextToSend - ts.byte);
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
                            socket.myWindow += (byteCount_t)(socket.nextToSend - ts.byte);
                            socket.theirWindow += (byteCount_t)(socket.nextToSend - ts.byte);
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
        if(!call timeQueue.empty()){
            call timeoutTimer.startOneShot(((call timeQueue.head()).expiration - call timeoutTimer.getNow()));
        }
    }

    /* == closeSocket ==
        Begins the teardown procedure by sending a FIN and updating state. 
        Called when the "clostConnection" command is called. */
    task void closeSocket(){
        socket_store_t socket;
        uint32_t IDtoClose;
        if(call IDstoClose.size()>0){
            IDtoClose = call IDstoClose.dequeue();
            if(call sockets.contains(IDtoClose)){
                socket = call sockets.get(IDtoClose);
                
                //Change socket state. Since the socket is closed, don't send data.
                if(socket.state==CLOSED){
                    //already closed, do nothing
                    return;
                }
                else if(socket.state==CLOSING){
                    socket.state = CLOSED;
                    dbg(TRANSPORT_CHANNEL, "INFO (teardown): Sent FIN to %d. State: CLOSED\n", socket.dest.addr);
                }
                else{
                    socket.state = WAIT_ACKFIN;
                    dbg(TRANSPORT_CHANNEL, "INFO (teardown): Sent FIN to %d. State: WAIT_ACKFIN\n", socket.dest.addr);
                }
                socket.myWindow = 0;
                socket.theirWindow = 0;
                call sockets.insert(IDtoClose, socket);

                //Send a FIN.
                sendSUTD(IDtoClose, FIN);
            }
            if(call IDstoClose.size()>0){
                post closeSocket();
            }
        }
    }

    task void checkSRtimeouts(){
        int num_queuedSockets = call sendRemoveQueue.size();
        int i=0;
        timestamp ts;
        uint32_t currentTime = call sendRemoveTimer.getNow();
        // dbg(TRANSPORT_CHANNEL,"INFO (SR stamps): Checking SR stamps. Q size %d\n",num_queuedSockets);
        for(i=0;i<num_queuedSockets;i++){
            // dbg(TRANSPORT_CHANNEL,"Checking")
            if(currentTime < (call sendRemoveQueue.head()).expiration){
                //this isn't expired, so nothing in the queue is expired
                // dbg(TRANSPORT_CHANNEL,"INFO Not expired yet. currentTime: %d, expiration: %d\n",currentTime,(call sendRemoveQueue.head()).expiration);
                break;
            }
            ts = call sendRemoveQueue.dequeue();
            if(ts.intent==CONNECTED){
                //Get and update the socket so it is ready to send data.
                socket_store_t socket = call sockets.get(ts.id);
                if(ts.expiration>=socket.trueSendTime){
                    socket.nextToWrite = socket.nextToSend;
                    socket.nextToRead = socket.nextExpected;
                    call sockets.insert(ts.id,socket);

                    dbg(TRANSPORT_CHANNEL, "INFO (setup): Socket %d Ready to send.\n",ts.id);
                    //Signal the connection is ready to use.
                    signal TinyController.connected(ts.id, call ports.get(socket.srcPort));
                    
                }
            }
            else if(ts.intent==WAIT_FINAL){
                if(call sockets.contains(ts.id)){
                    socket_store_t socket = call sockets.get(ts.id);
                    if(ts.expiration>=socket.expiration){
                        call sockets.remove(ts.id);
                        dbg(TRANSPORT_CHANNEL, "INFO (removal): removeDelay fired. Removing socket %d to %d. %d remaining sockets.\n", ts.id, socket.dest.addr, call sockets.size());
                    }
                    // else{
                    //     dbg(TRANSPORT_CHANNEL,"Not True expiration yet. expiration: %d, true expiration: %d\n",ts.expiration,socket.expiration);
                    // }
                }
                // else{
                //     dbg(TRANSPORT_CHANNEL,"WARNING (removal): Socket %d to remove does not exist\n",ts.id);
                // }
            }
            else if(ts.intent==CLOSING){
                call IDstoClose.enqueue(ts.id);
                dbg(TRANSPORT_CHANNEL, "INFO (closing): Socket %d ready to close\n",ts.id);
                post closeSocket();
            }
            else{
                dbg(TRANSPORT_CHANNEL,"ERROR (sendRemoveTimer): I don't know how to handle this.\n");
            }
        }
        if(!call sendRemoveTimer.isRunning() && call sendRemoveQueue.size()>0){
            uint32_t expires = (call sendRemoveQueue.head()).expiration;
            uint32_t current = call sendRemoveTimer.getNow();
            call sendRemoveTimer.startOneShot(expires-current);
        }
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
            uint8_t incomingDestPort = ((incomingMsg.ports) & 240)>>4;
            uint8_t incomingSrcPort = (incomingMsg.ports) & 15;
            uint32_t socketID = getSocketID(incomingMsg.src, incomingSrcPort, incomingDestPort);
            
            //Log the incoming pack.
            // dbg(TRANSPORT_CHANNEL, "INFO (transport): gotTCPack:\n");
            // logTCpack(&incomingMsg, TRANSPORT_CHANNEL);

            //If the socket this packet is trying to reach already exists,
            if(call sockets.contains(socketID)){
                //Get the requested socket for later.
                socket_store_t socket = call sockets.get(socketID);

                //Check to ensure the requested byte falls within a valid range (not a resend, and RIGHT NOW NOT HOLES EITHER)
                if((byteCount_t)(socket.nextExpected - incomingMsg.currbyte) > SOCKET_BUFFER_SIZE && socket.state == CONNECTED){
                    dbg(TRANSPORT_CHANNEL, "Unexpected Byte Order: Expected byte %d, got byte %d. Dropping Packet.\n",socket.nextExpected%SOCKET_BUFFER_SIZE, incomingMsg.currbyte%SOCKET_BUFFER_SIZE);
                    return;
                }

                //Check which flags the packet has to handle it accordingly.
                switch(incomingFlags){
                    //SYNC: 0 | ACK: 0 | FIN: 0 (DATA)
                    case(EMPTY): //Expected states: CONNECTED, for data transfer.
                        //If connected, then empty flag field implies packet contains data.
                        if(socket.state==CONNECTED){
                            //If room in buffer for the payload data (no holes),
                            if(((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE >= incomingSize || socket.nextToRead==socket.nextExpected){
                                tcpack acker;
                                //As long as there is new data, accept it.
                                if((byteCount_t)(incomingMsg.currbyte + incomingSize - socket.nextExpected) < SOCKET_BUFFER_SIZE){
                                    //If copying into the buffer does not require a wraparound, then directly copy.
                                    if(socket.nextExpected%SOCKET_BUFFER_SIZE+incomingSize<SOCKET_BUFFER_SIZE){
                                        memcpy(&(socket.recvBuff[incomingMsg.currbyte%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize);
                                        // dbg(TRANSPORT_CHANNEL, "INFO (buffer): Copied [%d, %d) (%d bytes). Buffer:\n", incomingMsg.currbyte%SOCKET_BUFFER_SIZE, (incomingMsg.currbyte+incomingSize)%SOCKET_BUFFER_SIZE, incomingSize);
                                        // printBuffer(socket.recvBuff, SOCKET_BUFFER_SIZE);
                                    }
                                    else{//Copying requires a buffer wraparound
                                        //Calculate the remaining bytes that do not fit in the remaining buffer before wrap.
                                        uint8_t overflow = incomingMsg.currbyte%SOCKET_BUFFER_SIZE+incomingSize-SOCKET_BUFFER_SIZE;
                                        // dbg(TRANSPORT_CHANNEL,"Looping Buffer, NE: %d, size: %d, overflow %d\n",socket.nextExpected,incomingSize,overflow);

                                        //Copy the bytes according to the wraparound.
                                        memcpy(&(socket.recvBuff[incomingMsg.currbyte%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize-overflow);
                                        memcpy(&(socket.recvBuff[0]),incomingMsg.data+incomingSize-overflow,overflow);
                                        
                                        //Print the buffer.
                                        // dbg(TRANSPORT_CHANNEL, "INFO (buffer): Copied [%d, %d) (%d bytes). Buffer:\n", incomingMsg.currbyte, incomingMsg.currbyte+incomingSize, incomingSize);
                                        // printBuffer(socket.recvBuff, SOCKET_BUFFER_SIZE);
                                    }

                                    //Update socket values.
                                    //breaks with holes or sliding window.
                                    socket.lastRecv = incomingMsg.currbyte+incomingSize;
                                    socket.nextExpected = incomingMsg.currbyte+incomingSize;
                                    call sockets.insert(socketID,socket);
                            
                                    //Tell the application that data is ready to receive.
                                    printBuffer(socket.recvBuff, SOCKET_BUFFER_SIZE);
                                    signal TinyController.gotData(socketID,(byteCount_t)(socket.nextExpected-socket.nextToRead));//signal how much contiguous data is ready
                                }
                                else{ //If older bytes (already know it isn't newer stuff cause not accepting holes)
                                    dbg(TRANSPORT_CHANNEL,"Duplicate Data: [%d,%d). Expecting %d\n",incomingMsg.currbyte, incomingMsg.currbyte+incomingSize, socket.nextExpected);
                                }

                                //Send an ACK for the data, duplicate or not.
                                makeTCPack(&acker,0,1,0,0,socketID,
                                    ((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE,
                                    noData());
                                call send.send(32,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&acker);
                                dbg(TRANSPORT_CHANNEL,"INFO (transportData): ACK [%d, %d). nextExpected: %d | window: %d. Data ready: %d NE: %d, NR: %d\n", incomingMsg.currbyte%SOCKET_BUFFER_SIZE, (incomingMsg.currbyte+incomingSize)%SOCKET_BUFFER_SIZE, socket.nextExpected%SOCKET_BUFFER_SIZE, (SOCKET_BUFFER_SIZE+socket.nextToRead - socket.nextExpected)%SOCKET_BUFFER_SIZE, (byteCount_t)(socket.nextExpected-socket.nextToRead), socket.nextExpected%SOCKET_BUFFER_SIZE, socket.nextToRead%SOCKET_BUFFER_SIZE);
                            }
                            else{ //No room in buffer. Drop packet.
                                dbg(TRANSPORT_CHANNEL,"No room in recvBuffer. nextToRead: %d, currbyte: %d, room: %d, IS: %d\n",socket.nextToRead,socket.nextExpected,(SOCKET_BUFFER_SIZE+socket.nextToRead - socket.nextExpected)%SOCKET_BUFFER_SIZE,incomingSize);
                            }
                        }
                        else{ //Unexpected state (not connected).
                            dbg(TRANSPORT_CHANNEL, "WARNING: EMPTY, state = %s\n", getPrinted(socket.state, TRUE));
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
                                dbg(TRANSPORT_CHANNEL,"INFO (setup): SYNC_ACK ACKED, Socket %d CONNECTED, nextExpected: %d\n",socketID, socket.nextExpected%SOCKET_BUFFER_SIZE);

                                //Signal that data is inbound.
                                signal TinyController.connected(socketID, call ports.get(socket.srcPort));
                                break;
                            //If connected, then could be ACKing data. Must update window.
                            case(CONNECTED):
                                // dbg(TRANSPORT_CHANNEL,"Got Ack. %d is expecting byte %d. My next byte is %d. Last Acked: %d\n",incomingMsg.src,incomingMsg.nextbyte,socket.nextToSend, socket.lastAcked);
                                
                                //If the probe timer is running, stop it immediately. A response was sent!
                                if(call probeTimer.isRunning()){
                                    call probeTimer.stop();
                                    dbg(TRANSPORT_CHANNEL, "INFO (flow): probeTimer stopped.\n");
                                }

                                //If the ACK is acking previously unACKed data, update the socket.
                                if((byteCount_t)(incomingMsg.nextbyte - socket.lastAcked) < SOCKET_BUFFER_SIZE){//if acking more stuff
                                    //Get the number of bytes acked to update window size.
                                    uint8_t bytesAcked = (byteCount_t)(incomingMsg.nextbyte - socket.lastAcked);
                                    dbg(TRANSPORT_CHANNEL, "INFO (window): [%d,%d) ACKed (%d bytes).\n", socket.lastAcked%SOCKET_BUFFER_SIZE, incomingMsg.nextbyte%SOCKET_BUFFER_SIZE, bytesAcked);
                                    // if(socket.myWindow+bytesAcked != incomingMsg.adWindow){
                                    //     dbg(TRANSPORT_CHANNEL, "WARNING (window): mismatch in windows. eff+acked: %d | ad: %d\n", socket.myWindow+bytesAcked, incomingMsg.adWindow);
                                    // }

                                    //Update the socket.
                                    socket.lastAcked = incomingMsg.nextbyte;
                                    socket.myWindow += bytesAcked;
                                    socket.theirWindow = incomingMsg.adWindow;
                                    call sockets.insert(socketID, socket);

                                    //If we have more data to send, and there isn't data in flight, then send the next piece!
                                    if(socket.nextToWrite!=socket.nextToSend && socket.myWindow > 0 && socket.theirWindow > 0){
                                        //Queue the data to send.
                                        call sendQueue.enqueue(socketID);
                                        post sendData();
                                        dbg(TRANSPORT_CHANNEL, "INFO (window): Posting send. myWindow: %d | theirWindow: %d\n", socket.myWindow, socket.theirWindow);
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
                                //Remove the socket if the ACK is for closing.
                                //Need to ensure this isn't an ACK for data that got delayed.
                                if(incomingMsg.adWindow == 0){
                                    call sockets.remove(socketID);
                                    dbg(TRANSPORT_CHANNEL, "INFO (teardown): FIN to %d ACKED. Removing socket %d. %d remaining sockets.\n", socket.dest.addr, socketID, call sockets.size());
                                }
                                else{
                                    dbg(TRANSPORT_CHANNEL, "WARNING (teardown): Data ACK in closing? Dropping.\n");
                                }
                                break;
                            //If waiting for an ACK and a FIN before closing, update to only wait for a FIN.
                            case(WAIT_ACKFIN): 
                                //Update socket state.
                                socket.state = WAIT_FIN;
                                socket.nextExpected++;
                                call sockets.insert(socketID, socket);
                                dbg(TRANSPORT_CHANNEL, "INFO (teardown): FIN to %d ACKED. State: WAIT_FIN\n", socket.dest.addr);
                                break;
                            //If only waiting for an ACK, begin socket removal process.
                            //Change this such that it sends an ACK now that it has seen both a FIN and ACK.
                            case(WAIT_ACK):
                                //Update socket state.
                                socket.state = WAIT_FINAL;
                                socket.nextExpected++;
                                call sockets.insert(socketID, socket);

                                //Now, send an ACK.
                                sendSUTD(socketID, ACK);
                                socket = call sockets.get(socketID);

                                {//timestamp scope
                                    timestamp ts;
                                    makeTimeStamp(&ts,socket.RTT,socketID,0,WAIT_FINAL);
                                    socket.expiration = call sendRemoveTimer.getNow()+socket.RTT;
                                    call sockets.insert(socketID, socket);
                                    call sendRemoveQueue.enqueue(ts);
                                    if(!call sendRemoveTimer.isRunning())call sendRemoveTimer.startOneShot(socket.RTT);
                                }
                                dbg(TRANSPORT_CHANNEL, "INFO (teardown): FIN to %d ACKED. State: WAIT_FINAL\n", socket.dest.addr);
                                
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
                                socket.state = CLOSING;
                                dbg(TRANSPORT_CHANNEL, "INFO (teardown): ACKED FIN to %d. State: CLOSING\n", socket.dest.addr);

                                signal TinyController.closing(socketID);
                                {//timestamp scope
                                    timestamp ts;
                                    makeTimeStamp(&ts,socket.RTT,socketID,0,CLOSING);
                                    call sendRemoveQueue.enqueue(ts);
                                    if(!call sendRemoveTimer.isRunning())call sendRemoveTimer.startOneShot(socket.RTT);
                                }
                                break;
                            //If waiting for an ACK and a FIN before closing, update to only wait for an ACK.
                            case(WAIT_ACKFIN):
                                socket.state = WAIT_ACK;

                                dbg(TRANSPORT_CHANNEL, "INFO (teardown): Got FIN from %d. State: WAIT_ACK\n", socket.dest.addr);
                                break;
                            //Static memory "IDtoClose" causes issues. Implement a queue.
                            //If waiting only for FIN, begin socket removal process.
                            case(WAIT_FIN):
                                socket.state = WAIT_FINAL;
                                dbg(TRANSPORT_CHANNEL, "INFO (teardown): ACKED FIN to %d. State: WAIT_FINAL\n", socket.dest.addr);

                                {//timestamp scope, removeDelay
                                    timestamp ts;
                                    makeTimeStamp(&ts,socket.RTT,socketID,0,WAIT_FINAL);
                                    socket.expiration = call sendRemoveTimer.getNow()+socket.RTT;
                                    call sockets.insert(socketID, socket);
                                    call sendRemoveQueue.enqueue(ts);
                                    if(!call sendRemoveTimer.isRunning())call sendRemoveTimer.startOneShot(socket.RTT);
                                }
                                break;
                            //If we get another FIN while waiting to remove the socket, restart the timer and send another ACK.
                            //This is a retransmission, so we decrement the expected sequence.
                            case(WAIT_FINAL):
                                {//timestamp scope, removeDelay
                                    timestamp ts;
                                    makeTimeStamp(&ts,socket.RTT,socketID,0,WAIT_FINAL);
                                    socket.expiration = call sendRemoveTimer.getNow()+socket.RTT;
                                    call sockets.insert(socketID, socket);
                                    call sendRemoveQueue.enqueue(ts);
                                    if(!call sendRemoveTimer.isRunning())call sendRemoveTimer.startOneShot(socket.RTT);
                                }
                                socket.nextExpected--;
                                socket.nextToSend--;
                                dbg(TRANSPORT_CHANNEL, "WARNING (teardown): ACKED FIN to %d. Restarting removeDelay.\n", socket.dest.addr);
                                break;
                            //If we get another FIN while waiting for an ACK in CLOSED or CLOSING, then original ACK was lost.
                            //Send another ACK.
                            case(CLOSED):
                            case(CLOSING):
                                socket.nextExpected--;
                                socket.nextToSend--;
                                dbg(TRANSPORT_CHANNEL, "WARNING: ACKED Retransmitted FIN to %d.\n", socket.dest.addr);
                                break;
                            //Unexpected state, therefore unknown behavior. Drop packet by returning.
                            default:
                                dbg(TRANSPORT_CHANNEL, "ERROR: ACKED FIN to %d, state = %s\n", socket.dest.addr, getPrinted(socket.state, TRUE));
                                return;
                        }
                        //Update the last Acked byte.
                        socket.lastAcked = incomingMsg.nextbyte;
                        
                        //The other side is closed, don't send data.
                        socket.myWindow = 0;
                        socket.theirWindow = 0;

                        //Update the socket's expected sequence.
                        socket.nextExpected++;
                        call sockets.insert(socketID, socket);

                        //Send the ACK.
                        if(socket.state != WAIT_ACK){ 
                            sendSUTD(socketID, ACK); 
                        }
                        break;
                    //SYNC: 1 | ACK: 1 | FIN: 0
                    case(SYNC_ACK): //Expect to be in SYNC_SENT state, otherwise unknown behavior.
                        //Response for our SYNC, update and respond with ACK
                        if(socket.state == SYNC_SENT){

                            //Update socket state. Previously unknown seq can be established.
                            socket.state = CONNECTED;
                            socket.nextExpected = incomingMsg.currbyte+1;
                            call sockets.insert(socketID, socket);

                            //Respond with an ACK.
                            sendSUTD(socketID, ACK);
                            socket = call sockets.get(socketID);
                            dbg(TRANSPORT_CHANNEL,"INFO (setup): ACKED SYNC_ACK, Socket %d CONNECTED, nextExpected: %d NTS: %d\n",socketID, socket.nextExpected%SOCKET_BUFFER_SIZE, socket.nextToSend);

                            //Prepare to send data.
                            {//timestamp scope
                                timestamp ts;
                                makeTimeStamp(&ts,socket.RTT,socketID,0,CONNECTED);
                                call sendRemoveQueue.enqueue(ts);
                                socket.trueSendTime = ts.expiration;
                                call sockets.insert(ts.id,socket);
                                if(!call sendRemoveTimer.isRunning()){
                                    call sendRemoveTimer.startOneShot(socket.RTT);
                                    dbg(TRANSPORT_CHANNEL,"SR Timer is now running. Q size: %d, duration: %d\n",call sendRemoveQueue.size(),socket.RTT);
                                }
                                else{
                                    dbg(TRANSPORT_CHANNEL,"SR Timer is already running\n");
                                }
                            }
                        }
                        //If we're connected, this is a retransmit. Restart the sendDelay and respond with an ACK.
                        else if(socket.state == CONNECTED){
                            //Respond with an ACK. Previous ACK lost, so decrement sequence.
                            socket.nextToSend--;
                            socket.lastAcked = incomingMsg.nextbyte;
                            call sockets.insert(socketID, socket);
                            sendSUTD(socketID, ACK);
                            socket = call sockets.get(socketID);
                            dbg(TRANSPORT_CHANNEL, "WARNING: Retransmitted SYNC_ACK. Restarting sendDelay.\n");

                            //Prepare to send data... again.
                            {//timestamp scope
                                timestamp ts;
                                makeTimeStamp(&ts,socket.RTT,socketID,0,CONNECTED);
                                call sendRemoveQueue.enqueue(ts);
                                socket.trueSendTime = ts.expiration;
                                call sockets.insert(ts.id,socket);
                                if(!call sendRemoveTimer.isRunning())call sendRemoveTimer.startOneShot(socket.RTT);
                            }
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
                    case(SYNC_ACK_FIN):
                        dbg(TRANSPORT_CHANNEL,"Warning: WTF FLAG. Closing Socket %d to %d and telling app.\n", socketID,incomingMsg.src);
                        signal TinyController.wtf(socketID);
                        call sockets.remove(socketID);
                        break;
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

                    dbg(TRANSPORT_CHANNEL, "INFO (setup): SYNC_ACK sent, new Socket:\n");
                    printSocket(socketID);
                }
                else{
                    if(incomingFlags!=SYNC_ACK_FIN){
                        tcpack wtf;
                        makeTCPack(&wtf,1,1,1,0,socketID,0,noData());
                        wtf.ports = (uint8_t)((incomingSrcPort<<4) + incomingDestPort);
                        wtf.src = TOS_NODE_ID;
                        wtf.dest = incomingMsg.src;
                        call send.send(32,wtf.dest,PROTOCOL_TCP,(uint8_t*)&wtf);
                        dbg(TRANSPORT_CHANNEL, "Warning: Unexpectedly flaged packet (%s) to non-existent socket %d from %d. Responding with wtf message.\n",getPrinted(incomingFlags, FALSE),socketID,incomingMsg.src);
                    }
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
            // dbg(TRANSPORT_CHANNEL, "PTL %d on Port %d\n",ptcl, portRequest);
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
        
        dbg(TRANSPORT_CHANNEL, "INFO (setup): SYNC sent, new Socket:\n");
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

        call IDstoClose.enqueue(socketID);
        post closeSocket();

        return SUCCESS;
    }

    /* == write ==
        Writes a given payload to a socket's sendBuffer, after checking for certain edge cases.
        (Does the socket exist, is there room in the buffer to write this, etc.)
        Called when an application with an existing connection has permission to write to a socket and wishes to do so. */
    command uint8_t TinyController.write(uint32_t socketID, uint8_t* payload, uint8_t length){
        socket_store_t socket;
        //Check to see if the socket exists
        if(call sockets.contains(socketID)){
            //If it does, retrieve it for later use.
            socket = call sockets.get(socketID);
            //If the socket is connected and ready to send data,
            if(socket.state == CONNECTED){
                //If the buffer is full, return 0.
                if((byteCount_t)(socket.lastAcked - socket.nextToWrite) == SOCKET_BUFFER_SIZE){ 
                    dbg(TRANSPORT_CHANNEL, "WARNING (write): Buffer is full. Cannot write.\n");
                    return 0; 
                }
                if(length>SOCKET_BUFFER_SIZE){
                    length=SOCKET_BUFFER_SIZE;
                }
                //Buffer is not full, take minimum between length and size.
                if(length > (byteCount_t)(socket.lastAcked-socket.nextToWrite)%SOCKET_BUFFER_SIZE && socket.lastAcked != socket.nextToWrite){
                        length = (byteCount_t)(socket.lastAcked-socket.nextToWrite)%SOCKET_BUFFER_SIZE;
                }

                //If the memory written to does not include a wraparound, write directly.
                if(socket.nextToWrite%SOCKET_BUFFER_SIZE+length<SOCKET_BUFFER_SIZE){
                    memcpy(&(socket.sendBuff[socket.nextToWrite%SOCKET_BUFFER_SIZE]),payload,length);
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
                dbg(TRANSPORT_CHANNEL, "INFO (buffer): Wrote %d bytes. Buffer:\n", length);
                printBuffer(socket.sendBuff, SOCKET_BUFFER_SIZE);

                return length;
            }
            else{ //Socket is not connected, and therefore cannot send.
                dbg(TRANSPORT_CHANNEL,"ERROR: Socket %d not connected.\n",socketID,socket.state);
                return 0;
            }
        }
        else{ //Socket was not found under the given socketID
            dbg(TRANSPORT_CHANNEL,"ERROR: No Socket %d.\n",socketID);
            return 0;
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

            dbg(TRANSPORT_CHANNEL, "DEBUG (Transport): Reading from %d, which has value %d\n", readSocket.nextToRead%SOCKET_BUFFER_SIZE, readSocket.recvBuff[readSocket.nextToRead%SOCKET_BUFFER_SIZE]);

            //Print the currently stored data.
            // dbg(TRANSPORT_CHANNEL, "INFO (buffer): Reading bytes. Buffer:\n");
            // printBuffer(readSocket.recvBuff, SOCKET_BUFFER_SIZE);

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
            //Update the socket's pointers to reflect this read action. Note this updates the window as well.
            readSocket.nextToRead+=length;
            call sockets.insert(socketID,readSocket);
            dbg(TRANSPORT_CHANNEL, "INFO (transportData): Read [%d,%d) (%d bytes).\n",(readSocket.nextToRead-length)%SOCKET_BUFFER_SIZE, readSocket.nextToRead%SOCKET_BUFFER_SIZE, length);
            return SUCCESS;
        }
        else{ //Socket does not exist.
            dbg(TRANSPORT_CHANNEL,"ERROR: No Socket %d.\n",socketID);
            return FAIL;
        }
    }

    command void TinyController.finishClose(uint32_t socketID){
        call IDstoClose.enqueue(socketID);
        post closeSocket();
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
    // event void closeDelay.fired(){
    //     post closeSocket();
    // }
    
    event void sendRemoveTimer.fired(){
        post checkSRtimeouts();
    }


    /* == sendDelay.fired ==
        called when the sendDelay timer is fired.
        This timer represents the delay necessary after sending an ACK to a SYNC_ACK before sending data.
        Once this timer fires, variables are updated and a signal that the socket is ready is sent to all applications.
        This obviously has security concerns. */
    // event void sendDelay.fired(){
    //     //As of right now, only the first socket sends data for a given simulation. 
    //     //A queue for sockets to signal they are ready to send must be implemented.
    //     uint32_t socketID = call sockets.getIndex(0);

    //     //Get and update the socket so it is ready to send data.
    //     socket_store_t socket = call sockets.get(socketID);
    //     socket.nextToWrite = socket.nextToSend;
    //     socket.nextToRead = socket.nextExpected;
    //     call sockets.insert(socketID,socket);

    //     //Signal the connection is ready to use.
    //     signal TinyController.connected(socketID);
        
    //     dbg(TRANSPORT_CHANNEL, "INFO (setup): Socket %d RTS.\n",socketID);
    // }

    /* == removeDelay.fired ==
        Called when the removeDelay timer fires.
        This timer is called when a client connection enters a WAIT_FINAL state.
        After this timer fires, the connection is assumed to be mutually closed, and the socket is removed from the client. */
    // event void removeDelay.fired(){
    //     //As of right now, this is done via a static "IDtoClose" variable. This should be changed to a queue of sockets to close.
    //     call sockets.remove(IDtoClose);
    //     dbg(TRANSPORT_CHANNEL, "INFO (socket): removeDelay fired. Removing socket %d. %d remaining sockets.\n", IDtoClose, call sockets.size());
    // }

    event void probeTimer.fired(){
        //send a 1-byte probe to see if the window is updated.
        post sendData();
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
        //Note that lastAcked initializes to the same value as nextToSend. This is the only time lastAcked >= nextToSend.
        memset(socket->sendBuff,(uint8_t)'_',SOCKET_BUFFER_SIZE);
        socket->nextToWrite = call Random.rand16();//Randomize sequence number 0, 255
        socket->lastAcked = socket->nextToWrite; //Nothing has been acknowledged because nothing's sent, it's new!
        socket->nextToSend = socket->nextToWrite; //Nothing has been sent, it's new!

        //Fill out the receiving portion of the socket.
        memset(socket->recvBuff,(uint8_t)'_',SOCKET_BUFFER_SIZE);
        socket->nextToRead = theirByte; //We may know their current byte they sent
        socket->nextExpected = theirByte+1; //The next byte will start as 1 more than their current byte!
        socket->lastRecv = theirByte; //This is the first time we've gotten something, let it have ID 0.

        //Arbitrary RTT, should be dynamic.
        socket->RTT = 4000;
        socket->expiration = call sendRemoveTimer.getNow() + 128000;
        //Initializing, we assume the whole buffer as a window.
        socket->myWindow = SOCKET_BUFFER_SIZE;
        socket->theirWindow = SOCKET_BUFFER_SIZE;

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
        tcpack sutdPack;
        timestamp ts;
        socket_store_t socket;
        if(!call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL,"ERROR (SUTD): Socket %d doesn't exist\n",socketID);
            return;
        }
        socket = call sockets.get(socketID);

        //Make the packet according to intent, and send it.
        switch(intent){
            case(EMPTY):
                dbg(TRANSPORT_CHANNEL, "ERROR: No intent for SUTD.\n");
                break;
            case(FIN):
                makeTCPack(&sutdPack, 0, 0, 1, 0, socketID, 0, noData());
                break;
            case(ACK):
                makeTCPack(&sutdPack, 0, 1, 0, 0, socketID, 0, noData());
                break;
            case(ACK_FIN):
                makeTCPack(&sutdPack, 0, 1, 1, 0, socketID, 0, noData());
                break;
            case(SYNC):
                makeTCPack(&sutdPack, 1, 0, 0, 0, socketID, SOCKET_BUFFER_SIZE, noData());
                break;
            case(SYNC_FIN):
                makeTCPack(&sutdPack, 1, 0, 1, 0, socketID, SOCKET_BUFFER_SIZE, noData());
                break;
            case(SYNC_ACK):
                makeTCPack(&sutdPack, 1, 1, 0, 0, socketID, SOCKET_BUFFER_SIZE, noData());
                break;
            case(SYNC_ACK_FIN):
                makeTCPack(&sutdPack, 1, 1, 1, 0, socketID, SOCKET_BUFFER_SIZE, noData());
                break;
            default:
                dbg(TRANSPORT_CHANNEL, "ERROR: Unknown intent: %d.\n",intent);
                break;
        }
        call send.send(32, socket.dest.addr, PROTOCOL_TCP, (uint8_t*) &sutdPack); 
        // dbg(TRANSPORT_CHANNEL, "INFO (transport): Sent TCPack:\n");
        // logTCpack(&sutdPack, TRANSPORT_CHANNEL);

        //Update the socket's sequence to reflect this information. Assume it is acked; if not, retransmit decrements lastAcked.
        socket.nextToSend++;
        socket.lastAcked++;
        call sockets.insert(socketID, socket);
        dbg(TRANSPORT_CHANNEL, "NextExp: %d, NTS: %d\n", socket.nextExpected, socket.nextToSend);

        //Add a timestamp for retransmission.
        makeTimeStamp(&ts, socket.RTT, socketID, socket.nextToSend, intent);
        call timeQueue.enqueue(ts);
        if(!call timeoutTimer.isRunning()){ 
            timeoutTime = (call timeQueue.empty()) ? socket.RTT : ((call timeQueue.head()).expiration - call timeoutTimer.getNow());
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
                if(socket.state == WAIT_ACKFIN || socket.state == WAIT_ACK || socket.state == CLOSED){ 
                    // dbg(TRANSPORT_CHANNEL, "WARNING (timeout): FIN unfulfilled (state: %s | expires in: %d).\n", getPrinted(socket.state, TRUE), (ts.expiration - call timeoutTimer.getNow()));
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
                    // dbg(TRANSPORT_CHANNEL, "WARNING (timeout): SYNC unfulfilled (state: %s | expires in: %d).\n", getPrinted(socket.state, TRUE), (ts.expiration - call timeoutTimer.getNow()));
                    return TRUE; }
                break;
            case(SYNC_FIN):
                //SYNC_FIN unimplemented as of now
                break;
            case(SYNC_ACK):
                if(socket.state == SYNC_RCVD){ 
                    // dbg(TRANSPORT_CHANNEL, "WARNING (timeout): SYNC_ACK unfulfilled (state: %s | expires in: %d).\n", getPrinted(socket.state, TRUE), (ts.expiration - call timeoutTimer.getNow()));
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
            dbg(TRANSPORT_CHANNEL, "INFO (socket): ID: %d | State: %s | myWindow: %d | theirWindow: %d | srcPort: %d | destPort: %d | src: %d | dest: %d\n",
                socketID,
                printedState,
                printedSocket.myWindow,
                printedSocket.theirWindow,
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
