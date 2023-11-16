#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcpack.h"
#include "../../includes/timeStamp.h"

module TinyControllerP{
    provides interface TinyController;

    uses interface Waysender as send;
    
    uses interface Hashmap<port_t> as ports;
    uses interface Hashmap<socket_store_t> as sockets;
    uses interface Queue<uint32_t> as sendQueue;
    uses interface Queue<tcpack> as receiveQueue;
    uses interface Queue<timestamp> as tsQueue;

    uses interface Timer<TMilli> as tsTimer;
    uses interface Timer<TMilli> as sendDelay;
    uses interface Timer<TMilli> as removeDelay; // Timer to remove the socket after moving to WAIT_FINAL state.
    uses interface Timer<TMilli> as closeDelay; // Dummy timer to signal the app has closed to move from CLOSING to CLOSED.

    uses interface Random;
}

implementation{
    tcpack storedMsg;
    uint32_t IDtoClose;//problems
    int timeoutTime=400;
    uint8_t readDataBuffer[SOCKET_BUFFER_SIZE];
    //Function Declarations
    enum flags{
        EMPTY = 0,
        FIN = 1,
        ACK = 2,
        ACK_FIN = 3,
        SYNC = 4,
        SYNC_FIN = 5,
        SYNC_ACK = 6,
        SYNC_ACK_FIN = 7};
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
    task void sendData();//currently not considering advertised window
    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID,uint8_t byte);
    uint32_t getSID(tcpack msg);

    void printTimeStamp(timestamp* ts){
        dbg(TRANSPORT_CHANNEL,"timestamp | currently: %d | expires: %d, id: %d, byte:%d\n",call tsTimer.getNow(),ts->expiration,ts->id,ts->byte);
    }

    task void checkTimeouts(){
        int i=0;
        int numInFlight = call tsQueue.size();
        uint32_t currentTime = call tsTimer.getNow();
        // dbg(TRANSPORT_CHANNEL,"Checking %d Timeouts. Current time: %d\n",numInFlight,currentTime);
        for(i=0;i<numInFlight;i++){
            timestamp ts = call tsQueue.dequeue();
            socket_store_t socket = call sockets.get(ts.id);
            // printTimeStamp(&ts);
            if(socket.lastAcked<=socket.nextToSend){//no wrap
                if(socket.lastAcked<=ts.byte && ts.byte<socket.nextToSend){//if byte not acked yet
                    if(currentTime>ts.expiration){
                        dbg(TRANSPORT_CHANNEL,"Timeout expired. LA:%d, byte: %d, NtS:%d | Resending from byte %d from socket %d\n",socket.lastAcked,ts.byte,socket.nextToSend,ts.byte,ts.id);
                        socket.nextToSend = ts.byte;//go back n scheme
                        call sockets.insert(ts.id,socket);
                        call sendQueue.enqueue(ts.id);
                        post sendData();
                        //don't requeue cause it expired and we're resending
                    }
                    else{
                        //requeue cause it hasn't expired yet and hasn't been acked yet
                        // dbg(TRANSPORT_CHANNEL,"Waiting for ack for timestamp:\n");
                        // printTimeStamp(&ts);
                        call tsQueue.enqueue(ts);
                    }
                }
                // else{dbg(TRANSPORT_CHANNEL,"No Wrap. Already got ack. LA: %d, Byte:%d, NtS:%d\n",socket.lastAcked,ts.byte,socket.nextToSend);}
            }
            else{//wrap around
                if(!(socket.nextToSend<ts.byte && ts.byte<socket.lastAcked)){//byte not inbetween (therefore not acked yet)
                    if(currentTime>ts.expiration){
                        dbg(TRANSPORT_CHANNEL,"Timeout expired. Resending from byte %d from socket %d\n",ts.byte,ts.id);
                        socket.nextToSend = ts.byte;//go back n scheme
                        call sockets.insert(ts.id,socket);
                        call sendQueue.enqueue(ts.id);
                        post sendData();
                    }
                    else{
                        // dbg(TRANSPORT_CHANNEL,"Waiting for ack for timestamp:\n");
                        // printTimeStamp(&ts);
                        call tsQueue.enqueue(ts);
                    }
                }
                // else{dbg(TRANSPORT_CHANNEL,"Wrap. Already got ack. LA: %d, Byte:%d, NtS:%d\n",socket.lastAcked,ts.byte,socket.nextToSend);}
            }
        }
        call tsTimer.startOneShot(timeoutTime);
    }
    
    bool isByteinFlight(uint32_t socketID, byteCount_t byte){
        int i=0;
        uint32_t numInFlight = call tsQueue.size();
        timestamp ts;
        for(i=0;i<numInFlight;i++){
            ts = call tsQueue.element(i);
            if(ts.id==socketID && ts.byte == byte){
                printTimeStamp(&ts);
                return TRUE;
            }
        }
        return FALSE;
    }
    //The brunt of the work - based on a connection state and flags, do something with the inbound packet.
    task void handlePack(){
        if(call receiveQueue.size()>0){
            tcpack incomingMsg = call receiveQueue.dequeue();
            uint8_t incomingFlags = (incomingMsg.flagsandsize & 224)>>5;
            uint8_t incomingSize = incomingMsg.flagsandsize & 31;
            uint8_t incomingSrcPort = ((incomingMsg.ports) & 240)>>4;
            uint8_t incomingDestPort = (incomingMsg.ports) & 15;
            
            uint32_t mySocketID = getSocketID(incomingMsg.src, incomingSrcPort, incomingDestPort);

            if(call sockets.contains(mySocketID)){
                socket_store_t mySocket = call sockets.get(mySocketID);
                if((byteCount_t)(mySocket.nextExpected - incomingMsg.currbyte) > SOCKET_BUFFER_SIZE && mySocket.state == CONNECTED){//may need to be changed for sliding window
                    dbg(TRANSPORT_CHANNEL, "Unexpected Byte Order: Expected byte %d, got byte %d. Currently not doing holes. Dropping Packet\n",mySocket.nextExpected, incomingMsg.currbyte);
                    return;//no holes allowed for now
                }

                switch(incomingFlags){
                    case(EMPTY):
                        if(mySocket.state==CONNECTED){//got Data (assuming incomingSize>0)
                            // dbg(TRANSPORT_CHANNEL,"Got Data. IncomingSize:%d\n",incomingSize);
                            // if(SOCKET_BUFFER_SIZE-((SOCKET_BUFFER_SIZE + (mySocket.nextToRead-mySocket.nextExpected))%SOCKET_BUFFER_SIZE)>=incomingSize){//if room in buffer including wrap around
                            if(((byteCount_t)(mySocket.nextToRead-mySocket.nextExpected))%SOCKET_BUFFER_SIZE >= incomingSize || mySocket.nextToRead==mySocket.nextExpected){//if room in this packet (no holes)
                                tcpack acker;
                                if(incomingMsg.currbyte==mySocket.nextExpected){//doesn't work for holes//if expecting this byte, copy data, update socket vars
                                    uint8_t recvBufftest[129];
                                    if(mySocket.nextExpected%SOCKET_BUFFER_SIZE+incomingSize<SOCKET_BUFFER_SIZE){//no wrap around to deal with
                                        // dbg(TRANSPORT_CHANNEL,"No wrap\n");
                                        memcpy(&(mySocket.recvBuff[mySocket.nextExpected%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize);
                                    }
                                    else{//buffer wrap around
                                        uint8_t overflow = mySocket.nextExpected%SOCKET_BUFFER_SIZE+incomingSize-SOCKET_BUFFER_SIZE;//calculate number of overflow bytes
                                        dbg(TRANSPORT_CHANNEL,"Looping Buffer, NE: %d, size: %d, overflow %d\n",mySocket.nextExpected,incomingSize,overflow);
                                        memcpy(&(mySocket.recvBuff[mySocket.nextExpected%SOCKET_BUFFER_SIZE]),incomingMsg.data,incomingSize-overflow);
                                        memcpy(&(mySocket.recvBuff[0]),incomingMsg.data+incomingSize-overflow,overflow);
                                        
                                        memcpy(&(recvBufftest[0]),&(mySocket.recvBuff[0]),SOCKET_BUFFER_SIZE);
                                        recvBufftest[128]=0;
                                        dbg(TRANSPORT_CHANNEL,"\nBuffer:\n|%s|\n",recvBufftest);
                                    }
                                    // dbg(TRANSPORT_CHANNEL,"NR:%d, NE:%d, Saved %d bytes to RecvBuff: '%s'\n",mySocket.nextToRead,mySocket.nextExpected,incomingSize,mySocket.recvBuff+mySocket.nextToRead);

                                    mySocket.lastRecv = incomingMsg.currbyte+incomingSize;//might be weird
                                    mySocket.nextExpected+=incomingSize;
                                }
                                else{//if older bytes (already know it isn't newer stuff cause not accepting holes)
                                    dbg(TRANSPORT_CHANNEL,"Duplicate Data from byte %d\n",incomingMsg.currbyte);
                                }
                                call sockets.insert(mySocketID,mySocket);
                                // ack duplicate data, cause maybe our previous ack was lost
                                makeTCPack(&acker,0,1,0,0,mySocketID,
                                    (mySocket.nextToRead-mySocket.nextExpected)%SOCKET_BUFFER_SIZE,//advertised window; negative mod may be problem
                                    noData());
                                call send.send(255,mySocket.dest.addr,PROTOCOL_TCP,(uint8_t*)&acker);
                                dbg(TRANSPORT_CHANNEL,"Got Bytes [%d, %d). Expecting Byte %d\n",incomingMsg.currbyte,incomingMsg.currbyte+incomingSize,mySocket.nextExpected);
                                
                                //don't incremement NtS because not actually sending data.
                                // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                // printSocket(mySocketID);
                                
                                signal TinyController.gotData(mySocketID,mySocket.nextExpected-mySocket.nextToRead);//signal how much contiguous data is ready
                            }
                            else{
                                dbg(TRANSPORT_CHANNEL,"No room in recvBuffer. nextToRead: %d, currbyte: %d, room: %d, IS: %d\n",mySocket.nextToRead,mySocket.nextExpected,(SOCKET_BUFFER_SIZE+mySocket.nextToRead - mySocket.nextExpected)%SOCKET_BUFFER_SIZE,incomingSize);
                            }
                        }
                        else{
                            dbg(TRANSPORT_CHANNEL,"Unexpected Empty Flags from node %d\n",incomingMsg.src);
                        }
                        break;
                    case(SYNC):
                        //if new packet, no socket, so wouldn't be here unless crash
                        //More logic required to detect a crash, etc.
                        dbg(TRANSPORT_CHANNEL, "SYNC->Crash Detection.\n");
                        break;
                    case(ACK):
                        switch(mySocket.state){
                            case(SYNC_RCVD):
                                //Signal that data is probably inbound!
                                mySocket.state = CONNECTED;
                                dbg(TRANSPORT_CHANNEL,"Connection Established for socket %d! nByte:%d\n",mySocketID,mySocket.nextExpected);
                                mySocket.nextExpected++;//part of handshake, need to increment expected byte
                                mySocket.nextToWrite = mySocket.nextToSend;
                                mySocket.nextToRead = mySocket.nextExpected;
                                call sockets.insert(mySocketID, mySocket);
                                // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                // printSocket(mySocketID);
                                signal TinyController.connected(mySocketID);//all apps connected to tcp know about all sockets
                                break;

                            case(CONNECTED):    //Received an ack to our data, update lastAcked, window, etc.
                                dbg(TRANSPORT_CHANNEL,"Got Ack. %d is expecting byte %d. My next byte is %d. Last Acked: %d\n",incomingMsg.src,incomingMsg.nextbyte,mySocket.nextToSend, mySocket.lastAcked);
                                // if(((byteCount_t)(mySocket.nextToSend-mySocket.lastAcked)<SOCKET_BUFFER_SIZE && (byteCount_t)(incomingMsg.nextbyte-mySocket.lastAcked)<SOCKET_BUFFER_SIZE) //no wrap
                                // || ((byteCount_t)(mySocket.nextToSend-mySocket.lastAcked)>SOCKET_BUFFER_SIZE && (byteCount_t)(incomingMsg.nextbyte-mySocket.lastAcked)>SOCKET_BUFFER_SIZE)){//wrap
                                if((byteCount_t)(incomingMsg.nextbyte - mySocket.lastAcked) < SOCKET_BUFFER_SIZE){//if acking more stuff
                                    //they have acknowledged more data
                                    // if((byteCount_t)(incomingMsg.nextbyte - mySocket.lastAcked) < SOCKET_BUFFER_SIZE){//if acking more stuffd
                                        mySocket.lastAcked = incomingMsg.nextbyte;
                                    // }
                                    call sockets.insert(mySocketID, mySocket);
                                    // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                    // printSocket(mySocketID);
                                    if(mySocket.nextToWrite!=mySocket.nextToSend && !isByteinFlight(mySocketID,incomingMsg.nextbyte)){//breaks for sliding window
                                        // dbg(TRANSPORT_CHANNEL,"More data to send\n");
                                        call sendQueue.enqueue(mySocketID);
                                        post sendData();
                                    }
                                }
                                else{
                                    if(mySocket.nextToSend!=mySocket.lastAcked){//if == then empty buffer, if != then difference == buff size so full
                                        dbg(TRANSPORT_CHANNEL,"SendBuff for socket %d is full\n", mySocketID);
                                    }
                                    else{
                                        dbg(TRANSPORT_CHANNEL,"I already know they got these bytes!\n");
                                    }
                                }
                                break;

                            case(WAIT_ACKFIN):
                                mySocket.state = WAIT_FIN;
                                mySocket.nextExpected++;
                                call sockets.insert(mySocketID, mySocket);
                                // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                // printSocket(mySocketID);
                                break;
                            
                            case(CLOSED):
                                call sockets.remove(mySocketID);
                                dbg(TRANSPORT_CHANNEL, "Final Ack received. Removing socket %d. | %d Remaining sockets\n",mySocketID,call sockets.size());
                                // dbg(TRANSPORT_CHANNEL,"Timestamps left:%d\n",call tsQueue.size());
                                // {
                                // timestamp ts = call tsQueue.head();
                                // printTimeStamp(&ts);
                                // }
                                break;
                            
                            case(WAIT_ACK):
                                mySocket.state = WAIT_FINAL;

                                call sockets.insert(mySocketID, mySocket);
                                // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                // printSocket(mySocketID);

                                IDtoClose = mySocketID;//fix this
                                call removeDelay.startOneShot(2*mySocket.RTT);
                                break;

                            default:
                                dbg(TRANSPORT_CHANNEL, "Unexpected ACK.\n");
                                break;
                        }
                        break;
                    case(FIN):
                        if(mySocket.state == CONNECTED){
                            //signal closing, then get told we're closed. For now we do this via a timer.
                            IDtoClose = mySocketID;
                            call closeDelay.startOneShot(mySocket.RTT);
                            mySocket.state = CLOSING;
                        }
                        else if(mySocket.state == WAIT_ACKFIN){
                            mySocket.state = WAIT_ACK;
                        }
                        else if(mySocket.state == WAIT_FIN){
                            mySocket.state = WAIT_FINAL;
                            IDtoClose = mySocketID;
                            call removeDelay.startOneShot(2*mySocket.RTT);
                        }
                        mySocket.lastAcked = incomingMsg.nextbyte;
                        
                        { // NOW ENTERING: THE ACK SCOPE
                            tcpack ackPack;
                            // dbg(TRANSPORT_CHANNEL,"1\n");
                            mySocket.nextExpected++;
                            call sockets.insert(mySocketID, mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);

                            makeTCPack(&ackPack, 0, 1, 0, 0, mySocketID, 1, noData());
                            call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                            // dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                            // logTCpack(&ackPack, TRANSPORT_CHANNEL);
                            mySocket.nextToSend++;
                            call sockets.insert(mySocketID,mySocket);
                        }
                        break;

                    case(SYNC_ACK):
                        if(mySocket.state == SYNC_SENT){
                            tcpack ackPack;
                            mySocket.state = CONNECTED;
                            mySocket.nextExpected = incomingMsg.currbyte+1;

                            dbg(TRANSPORT_CHANNEL,"Connection Established for socket %d!\n",mySocketID);
                            makeTCPack(&ackPack, 0, 1, 0, 0, mySocketID, 1, noData());
                            call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                            // dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                            // logTCpack(&ackPack, TRANSPORT_CHANNEL);
                            // dbg(TRANSPORT_CHANNEL,"2\n");
                            mySocket.nextToSend++;//in set up need to increment even though no data
                            // mySocket.nextExpected++;//why or why not
                            call sockets.insert(mySocketID, mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);

                            call sendDelay.startOneShot(mySocket.RTT);
                        }
                        else{
                            dbg(TRANSPORT_CHANNEL, "Unexpected SYNC_ACK. Dropping.\n");
                        }
                        break;
                    case(ACK_FIN):
                        dbg(TRANSPORT_CHANNEL, "ACK_FIN received.\n");
                        break;
                    default:
                        dbg(TRANSPORT_CHANNEL, "ERROR: unknown flag combo: %d. Dropping.\n", incomingFlags);
                        break;
                }
            }
            else{ //No socket
                if(incomingFlags == SYNC && call ports.contains(incomingDestPort)){
                    socket_store_t newSocket;
                    tcpack syncackPack;

                    createSocket(&newSocket, SYNC_RCVD, incomingDestPort, incomingSrcPort, incomingMsg.src, incomingMsg.currbyte);

                    makeTCPack(&syncackPack, 1, 1, 0, 0, mySocketID, 1, noData());
                    call send.send(255, incomingMsg.src, PROTOCOL_TCP, (uint8_t*) &syncackPack);
                    // dbg(TRANSPORT_CHANNEL, "Sent SYNCACK:\n");
                    // logTCpack(&syncackPack, TRANSPORT_CHANNEL);
                    // dbg(TRANSPORT_CHANNEL,"3\n");
                    newSocket.nextToSend++;
                    call sockets.insert(mySocketID, newSocket);
                    dbg(TRANSPORT_CHANNEL, "New Socket:\n");
                    printSocket(mySocketID);
                }
                else{
                    dbg(TRANSPORT_CHANNEL, "Nonsense flags %d OR Empty Port: %d. Dropping.\n",incomingFlags,incomingDestPort);
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
        tcpack syncPack;
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

        makeTCPack(&syncPack, 1, 0, 0, 0, socketID, 1, noData());//needs to change for window
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &syncPack);
        // dbg(TRANSPORT_CHANNEL, "Sent SYNC:\n");
        // logTCpack(&syncPack, TRANSPORT_CHANNEL);
        // dbg(TRANSPORT_CHANNEL,"4\n");
        newSocket.nextToSend++;//in handshake need to increment even though no data
        call sockets.insert(socketID, newSocket);
        
        dbg(TRANSPORT_CHANNEL, "New Socket:\n");
        printSocket(socketID);
        return socketID;
    }

    task void closeSocket(){
        socket_store_t socket;
        tcpack finPack;
        
        socket = call sockets.get(IDtoClose);
        socket.state = WAIT_ACKFIN;

        makeTCPack(&finPack, 0, 0, 1, 0, IDtoClose, 1, noData());
        call send.send(255, socket.dest.addr, PROTOCOL_TCP, (uint8_t*) &finPack);
        dbg(TRANSPORT_CHANNEL, "Sent FIN:\n");
        logTCpack(&finPack, TRANSPORT_CHANNEL);
        // dbg(TRANSPORT_CHANNEL,"5\n");        
        socket.nextToSend++;//in teardown need to increment even though no data
        // socket.nextExpected++;
        call sockets.insert(IDtoClose, socket);
        dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
        printSocket(IDtoClose);
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

    task void sendData(){//currently not considering advertised window
        uint32_t socketID;
        socket_store_t socket;
        uint8_t length;
        tcpack packet;
        if(call sendQueue.size()>0){
            socketID = call sendQueue.dequeue();
            socket = call sockets.get(socketID);
            if(socket.nextToSend!=socket.nextToWrite){//need to switch to window based, needs wraparound
                timestamp ts;
                length = (((byteCount_t)(socket.nextToWrite-socket.nextToSend))>tc_max_pld_len) ? tc_max_pld_len : ((byteCount_t)(socket.nextToWrite-socket.nextToSend));
                // solution here... no wraparound in reading buffer when making Tcp pack!
                // also change maketcp pack so it takes socketid and handles everything itself
                makeTCPack(&packet,0,0,0,length,socketID,
                            ((byteCount_t)(socket.nextToRead-socket.nextExpected))%SOCKET_BUFFER_SIZE,
                            socket.nextToSend);
                // logTCpack(&packet,TRANSPORT_CHANNEL);
                call send.send(255,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&packet);
                dbg(TRANSPORT_CHANNEL,"Sent data from byte %d!\n",socket.nextToSend);
                makeTimeStamp(&ts,2*socket.RTT,socketID,socket.nextToSend);
                socket.nextToSend+=length;
                call sockets.insert(socketID,socket);
                call tsQueue.enqueue(ts);
                // dbg(TRANSPORT_CHANNEL,"timestamps left: %d\n",call tsQueue.size());
                // printTimeStamp(&ts);
                if(!call tsTimer.isRunning()){
                    call tsTimer.startOneShot(timeoutTime);
                }
            }
            else{
                dbg(TRANSPORT_CHANNEL,"No data in sendBuffer of socket %d\n",socketID);
            }
        }
        else{
            dbg(TRANSPORT_CHANNEL,"Nothing in sendQueue\n");
        }
    }

    //may cause seg faults, double check exact byte math!
    command error_t TinyController.write(uint32_t socketID, uint8_t* payload, uint8_t length){
        socket_store_t socket;
        if(call sockets.contains(socketID)){
            socket = call sockets.get(socketID);
            if(socket.state == CONNECTED){
                if(((byteCount_t)(socket.lastAcked-socket.nextToWrite))%SOCKET_BUFFER_SIZE>=length || socket.lastAcked==socket.nextToWrite){
                    uint8_t sendBufftest[129];
                    if(socket.nextToWrite%SOCKET_BUFFER_SIZE+length<SOCKET_BUFFER_SIZE){
                        memcpy(&(socket.sendBuff[socket.nextToWrite%SOCKET_BUFFER_SIZE]),payload,length);
                    }
                    else{//buffer wrap around
                        uint8_t overflow = socket.nextToWrite%SOCKET_BUFFER_SIZE+length-SOCKET_BUFFER_SIZE;
                        memcpy(&(socket.sendBuff[socket.nextToWrite%SOCKET_BUFFER_SIZE]),payload,length-overflow);
                        memcpy(&(socket.sendBuff[0]),payload+length-overflow,overflow);
                    }
                    memcpy(&(sendBufftest[0]),&(socket.sendBuff[0]),SOCKET_BUFFER_SIZE);
                    sendBufftest[128]=0;
                    dbg(TRANSPORT_CHANNEL,"Wrote data to buffer!\nBuffer:\n|%s|\n",sendBufftest);
                    socket.nextToWrite+=length;
                    call sockets.insert(socketID,socket);
                    call sendQueue.enqueue(socketID);
                    post sendData();
                    return SUCCESS;
                }
                else{
                    dbg(TRANSPORT_CHANNEL,"Can't Write. Not enough room in sendbuffer. lastAcked: %d, nextToWrite: %d, room: %d, length: %d\n",socket.lastAcked,socket.nextToWrite,((byteCount_t)(socket.lastAcked-socket.nextToWrite))%SOCKET_BUFFER_SIZE,length);
                    return FAIL;
                }
            }
            else{
                dbg(TRANSPORT_CHANNEL,"Socket %d in state %d, not CONNECTED state\n",socketID,socket.state);
                return FAIL;
            }
        }
        else{
            dbg(TRANSPORT_CHANNEL,"Socket %d doesn't exist\n",socketID);
            return FAIL;
        }

    }

    command error_t TinyController.read(uint32_t socketID,uint8_t length,uint8_t* location){
        if(call sockets.contains(socketID)){
            socket_store_t readSocket = call sockets.get(socketID);
            uint8_t recvBufftest[129];
            memcpy(&(recvBufftest[0]),&(readSocket.recvBuff[0]),SOCKET_BUFFER_SIZE);
            recvBufftest[128]=0;
            dbg(TRANSPORT_CHANNEL,"About to read from recvBuffer!\nBuffer:\n|%s|\n",recvBufftest);
            // memset(location,0,SOCKET_BUFFER_SIZE);//don't think tc should be responsible for 0ing out the output space
            if(readSocket.nextToRead%SOCKET_BUFFER_SIZE+length<SOCKET_BUFFER_SIZE){//check if portion to be read requires wraparound handling
                memcpy(location,&(readSocket.recvBuff[readSocket.nextToRead%SOCKET_BUFFER_SIZE]),length);
            }
            else{//buffer wrap around
                uint8_t overflow = readSocket.nextToRead%SOCKET_BUFFER_SIZE+length-SOCKET_BUFFER_SIZE;//calculate how many bytes are wrapped around
                memcpy(location,&(readSocket.recvBuff[readSocket.nextToRead%SOCKET_BUFFER_SIZE]),length-overflow);//copy till end of buffer
                memcpy(location+length-overflow,&(readSocket.recvBuff[0]),overflow);//copy wrap around stuff
            }
            readSocket.nextToRead+=length;
            call sockets.insert(socketID,readSocket);
            return SUCCESS;
        }
        else{
            dbg(TRANSPORT_CHANNEL,"Can't Read from nonexistent Socket %d\n",socketID);
            return FAIL;
        }
    }

    event void send.gotTCP(uint8_t* pkt){
        memcpy(&storedMsg, (tcpack*)pkt, tc_pkt_len);
        call receiveQueue.enqueue(storedMsg);
        post handlePack();
        // dbg(TRANSPORT_CHANNEL, "Got TCpack\n");
        // logTCpack((tcpack*)pkt, TRANSPORT_CHANNEL);
    }

    event void tsTimer.fired(){
        post checkTimeouts();
    }

    event void closeDelay.fired(){//need to change advertised window
        tcpack finPack;
        socket_store_t mySocket = call sockets.get(IDtoClose);

        mySocket.state = CLOSED;

        makeTCPack(&finPack, 0, 0, 1, 0, IDtoClose, 1, noData());
        call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &finPack);
        dbg(TRANSPORT_CHANNEL, "Sent FIN:\n");
        logTCpack(&finPack, TRANSPORT_CHANNEL);
        // dbg(TRANSPORT_CHANNEL,"6\n");
        mySocket.nextToSend++;
        call sockets.insert(IDtoClose, mySocket);
        dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
        printSocket(IDtoClose);
    }

    //need to signal correct socket
    event void sendDelay.fired(){
        //This will eventually signal that data is ready to be sent, but for now I'm testing teardown.
        uint32_t socketID = call sockets.getIndex(0);//wrong!!
        socket_store_t socket = call sockets.get(socketID);
        socket.nextToWrite = socket.nextToSend;
        socket.nextToRead = socket.nextExpected;
        call sockets.insert(socketID,socket);
        signal TinyController.connected(socketID);//all apps connected to tcp know about all sockets
        
        dbg(TRANSPORT_CHANNEL, "Ready to Send Data on socket %d!\n",socketID);
    }

    event void removeDelay.fired(){
        call sockets.remove(IDtoClose);
        dbg(TRANSPORT_CHANNEL, "Initiated Fin. %d agreed. Removing socket %d. | %d Remaining sockets\n",IDtoClose & 255,IDtoClose,call sockets.size());
        // dbg(TRANSPORT_CHANNEL,"Timestamps left:%d\n",call tsQueue.size());
        // {
        // timestamp ts = call tsQueue.head();
        // printTimeStamp(&ts);
        // }

    }

    void createSocket(socket_store_t* socket, uint8_t state, socket_port_t srcPort, socket_port_t destPort, uint8_t dest, uint8_t theirByte){
        socket_addr_t newDest;
        newDest.port = destPort;
        newDest.addr = dest;
        
        // socket->flag = flag;
        socket->state = state;
        socket->srcPort = srcPort;
        socket->dest = newDest;

        memset(socket->sendBuff,42,SOCKET_BUFFER_SIZE);//42 is *
        socket->nextToWrite = call Random.rand16();//Randomize sequence number 0, 255
        socket->lastAcked = socket->nextToWrite-1; //Nothing has been acknowledged because nothing's sent, it's new!
        socket->nextToSend = socket->nextToWrite; //Nothing has been sent, it's new!

        memset(socket->recvBuff,42,SOCKET_BUFFER_SIZE);//42 is *
        socket->nextToRead = theirByte; //We may know their current byte they sent
        socket->nextExpected = theirByte+1; //The next byte will start as 1 more than their current byte!
        socket->lastRecv = theirByte; //This is the first time we've gotten something, let it have ID 0.

        socket->RTT = 2000;

        call sockets.insert(getSocketID(dest,destPort,srcPort),*socket);
    }

    void makeTCPack(tcpack* pkt, uint8_t sync, uint8_t ack, uint8_t fin, uint8_t size, uint32_t socketID, uint8_t adWindow, uint8_t byteIndex){
        // memset(pkt,0,tc_pkt_len);
        uint8_t flagField = 0;
        uint8_t portField = 0;
        socket_store_t socket = call sockets.get(socketID);
        if(!call sockets.contains(socketID))dbg(TRANSPORT_CHANNEL,"Socket doesn't exist yet %d\n",socketID);

        //(left->right): 0000 0000
        //SYNC,ACK,FIN,size[5]
        flagField += sync<<7;
        flagField += ack<<6;
        flagField += fin<<5;
        flagField += (size & 31);
        pkt->flagsandsize = flagField;
        
        //(left->right): 0000 0000
        //destPort, srcPort
        portField += socket.dest.port<<4;
        portField += (socket.srcPort & 15);
        pkt->ports = portField;
        pkt->src = TOS_NODE_ID;
        pkt->dest = socket.dest.addr;
        pkt->currbyte = socket.nextToSend;
        pkt->nextbyte = socket.nextExpected;
        pkt->adWindow = adWindow;
     
        memset(pkt->data,0,tc_max_pld_len);
        if(size>0){
            if(byteIndex%SOCKET_BUFFER_SIZE+size<SOCKET_BUFFER_SIZE){//no wrap
                memcpy(pkt->data, &(socket.sendBuff[byteIndex%SOCKET_BUFFER_SIZE]), size);
            }
            else{
                uint8_t overflow = byteIndex%SOCKET_BUFFER_SIZE+size-SOCKET_BUFFER_SIZE;
                memcpy(pkt->data,&(socket.sendBuff[byteIndex%SOCKET_BUFFER_SIZE]),size-overflow);
                memcpy(pkt->data+size-overflow,&(socket.sendBuff[0]),overflow);
            }
        }
    }

    void printSocket(uint32_t socketID){
        if(!call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL, "ERROR: No socket with ID %d exists.\n",socketID);
        }
        else{
            socket_store_t printedSocket = call sockets.get(socketID);
            char* printedState;
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
            dbg(TRANSPORT_CHANNEL, "PRINTING SOCKET: ID: %d | State: %s | srcPort: %d | destPort: %d | src: %d | dest: %d\n",
                socketID,
                printedState,
                printedSocket.srcPort,
                printedSocket.dest.port,
                TOS_NODE_ID,
                printedSocket.dest.addr
            );
        }
    }

    uint32_t getSocketID(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        return  (srcPort<<24) + (destPort<<16) + (TOS_NODE_ID<<8) +dest;
    }

    uint32_t getSID(tcpack msg){
        uint8_t incomingSrcPort = (msg.ports & 240)>>4;
        uint8_t incomingDestPort = (msg.ports) & 15;
        
        return getSocketID(msg.src, incomingSrcPort, incomingDestPort);        
    }

    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID,uint8_t byte){
        ts->expiration = call tsTimer.getNow()+timeout;
        ts->id = socketID;
        ts->byte = byte;
    }

    uint8_t noData(){
        return 0;
    }
}