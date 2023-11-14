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
    uint32_t IDtoClose;
    socket_store_t readSocket;
    int timeoutTime=400;
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
        uint16_t          destSeq);
    void makeTCPack(
        tcpack* pkt,
        uint8_t sync,
        uint8_t ack,
        uint8_t fin,
        uint8_t size,
        uint8_t dPort,
        uint8_t sPort,
        uint8_t dest,
        uint8_t src,
        uint8_t adWindow,
        uint16_t seq,
        uint16_t nextExp,
        uint8_t* data);
    uint32_t getSocketID(uint8_t dest, uint8_t destPort, uint8_t srcPort);
    uint8_t* noData();
    void printSocket(uint32_t socketID);
    task void sendData();//currently not considering advertised window
    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID,uint16_t seq, uint8_t byte);
    uint32_t getSID(tcpack msg);

    void printTimeStamp(timestamp* ts){
        dbg(TRANSPORT_CHANNEL,"timestamp: exp: %d | id: %d | seq:%d | byte:%d\n",ts->expiration,ts->id,ts->seq,ts->byte);
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
                if(socket.lastAcked<ts.byte && ts.byte<socket.nextToSend){//if byte not acked yet
                    if(currentTime>ts.expiration){
                        dbg(TRANSPORT_CHANNEL,"Timeout expired. LS:%d, byte: %d, NtS:%d | Resending seq %d with byte %d from socket %d\n",socket.lastAcked,ts.byte,socket.nextToSend,ts.seq,ts.byte,ts.id);
                        socket.nextToSend = ts.byte;//go back n scheme
                        socket.seq = ts.seq-1;
                        call sockets.insert(ts.id,socket);
                        call sendQueue.enqueue(ts.id);
                        post sendData();
                    }
                    else{
                        call tsQueue.enqueue(ts);
                    }
                }
                // else{dbg(TRANSPORT_CHANNEL,"No Wrap. Already got ack %d. LA: %d, Byte:%d, NtS:%d\n",ts.seq,socket.lastAcked,ts.byte,socket.nextToSend);}
            }
            else{//wrap around
                if(!(socket.nextToSend<ts.byte && ts.byte<socket.lastAcked)){//byte not inbetween (therefore not acked yet)
                    if(currentTime>ts.expiration){
                        dbg(TRANSPORT_CHANNEL,"Timeout expired. Resending seq %d with byte %d from socket %d\n",ts.seq,ts.byte,ts.id);
                        socket.nextToSend = ts.byte;//go back n scheme
                        socket.seq = ts.seq-1;
                        call sockets.insert(ts.id,socket);
                        call sendQueue.enqueue(ts.id);
                        post sendData();
                    }
                    else{
                        call tsQueue.enqueue(ts);
                    }
                }
                else{dbg(TRANSPORT_CHANNEL,"Wrap. Already got ack %d\n",ts.seq);}
            }
        }
        if(call tsQueue.size()>0)call tsTimer.startOneShot(timeoutTime);
    }
    
    //The brunt of the work - based on a connection state and flags, do something with the inbound packet.
    task void handlePack(){
        tcpack incomingMsg = call receiveQueue.dequeue();
        uint8_t incomingFlags = (incomingMsg.flagsandsize & 224)>>5;
        uint8_t incomingSize = incomingMsg.flagsandsize & 31;
        uint8_t incomingSrcPort = ((incomingMsg.ports) & 240)>>4;
        uint8_t incomingDestPort = (incomingMsg.ports) & 15;
        
        uint32_t mySocketID = getSocketID(incomingMsg.src, incomingSrcPort, incomingDestPort);

        if(call sockets.contains(mySocketID)){
            socket_store_t mySocket = call sockets.get(mySocketID);
            if(mySocket.seqToRecv < incomingMsg.seq && mySocket.state != SYNC_SENT){
                dbg(TRANSPORT_CHANNEL, "Unexpected Seq Order: Expected %d, got %d. Dropping Packet\n",mySocket.seqToRecv, incomingMsg.seq);
                return;//no holes allowed for now
            }
            else{
                mySocket.seqToRecv++;
            }

            switch(incomingFlags){
                case(EMPTY):
                    if(mySocket.state==CONNECTED){//got Data
                        // dbg(TRANSPORT_CHANNEL,"Got Data. IncomingSize:%d\n",incomingSize);
                        if(SOCKET_BUFFER_SIZE-((SOCKET_BUFFER_SIZE + (mySocket.nextToRead-mySocket.nextExpected))%SOCKET_BUFFER_SIZE)>=incomingSize){//if room in buffer including wrap around
                            tcpack acker;
                            if(incomingMsg.seq==mySocket.seqToRecv-1){
                                if(mySocket.nextExpected+incomingSize<SOCKET_BUFFER_SIZE){
                                    // dbg(TRANSPORT_CHANNEL,"No wrap\n");
                                    memcpy(&(mySocket.recvBuff[mySocket.nextExpected]),incomingMsg.data,incomingSize);
                                }
                                else{//buffer wrap around
                                    uint8_t remaining = mySocket.nextExpected+incomingSize-SOCKET_BUFFER_SIZE;
                                    // dbg(TRANSPORT_CHANNEL,"Looping Buffer\n");
                                    memcpy(&(mySocket.recvBuff[mySocket.nextExpected]),incomingMsg.data,remaining);
                                    memcpy(&(mySocket.recvBuff[0]),&(incomingMsg.data[0])+remaining,incomingSize-remaining);
                                }
                                // dbg(TRANSPORT_CHANNEL,"NR:%d, NE:%d, Saved %d bytes to RecvBuff: '%s'\n",mySocket.nextToRead,mySocket.nextExpected,incomingSize,mySocket.recvBuff+mySocket.nextToRead);

                                mySocket.lastRecv = (mySocket.nextExpected+incomingSize) % SOCKET_BUFFER_SIZE;
                                mySocket.nextExpected+=incomingSize;
                                mySocket.seq++;
                            }
                            else{
                                mySocket.seqToRecv = incomingMsg.seq+1;//problem for sliding window 
                            }
                            makeTCPack(&acker,0,1,0,incomingSize,
                                incomingSrcPort,incomingDestPort,incomingMsg.src,TOS_NODE_ID,
                                (SOCKET_BUFFER_SIZE+mySocket.nextToRead-mySocket.nextExpected)%SOCKET_BUFFER_SIZE,
                                mySocket.seq,mySocket.seqToRecv,noData());
                            call send.send(255,mySocket.dest.addr,PROTOCOL_TCP,(uint8_t*)&acker);
                            dbg(TRANSPORT_CHANNEL,"Got seq %d. Acking %d. mySeq:%d\n",incomingMsg.seq,mySocket.seqToRecv,mySocket.seq);
                            call sockets.insert(mySocketID,mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);
                            
                            signal TinyController.gotData(mySocketID,mySocket.nextExpected-mySocket.nextToRead);
                        }
                        else{
                            dbg(TRANSPORT_CHANNEL,"No room in buffer. nextToRead: %d, nextExpected: %d, room: %d, IS: %d\n",mySocket.nextToRead,mySocket.nextExpected,(SOCKET_BUFFER_SIZE+mySocket.nextToRead - mySocket.nextExpected)%SOCKET_BUFFER_SIZE,incomingSize);
                        }
                    }
                    else{
                        dbg(TRANSPORT_CHANNEL,"Empty Flags\n");
                    }
                    break;
                case(SYNC):
                    //More logic required to detect a crash, etc.
                    dbg(TRANSPORT_CHANNEL, "SYNC->Crash Detection.\n");
                    break;
                case(ACK):
                    switch(mySocket.state){
                        case(SYNC_RCVD):
                            //Signal that data is probably inbound!
                            mySocket.state = CONNECTED;
                            dbg(TRANSPORT_CHANNEL,"Connection Established for socket %d!\n",mySocketID);
                            call sockets.insert(mySocketID, mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);
                            signal TinyController.connected(mySocketID);//all apps connected to tcp know about all sockets
                            break;

                        case(CONNECTED):    //Received an ack to our data, update window, etc.
                            dbg(TRANSPORT_CHANNEL,"Got Ack %d. Their seq: %d. SeqToRecv: %d\n",incomingMsg.nextExp,incomingMsg.seq,mySocket.seqToRecv);
                            if(incomingMsg.nextExp>mySocket.seq){
                                mySocket.lastAcked = (mySocket.lastAcked+incomingSize)%SOCKET_BUFFER_SIZE;
                                call sockets.insert(mySocketID, mySocket);
                                // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                // printSocket(mySocketID);
                                if(mySocket.nextToWrite!=mySocket.nextToSend){
                                    call sendQueue.enqueue(mySocketID);
                                    post sendData();
                                }
                            }
                            else{dbg(TRANSPORT_CHANNEL,"Duplicate Ack\n");}
                            break;

                        case(WAIT_ACKFIN):
                            mySocket.state = WAIT_FIN;

                            call sockets.insert(mySocketID, mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);
                            break;
                        
                        case(CLOSED):
                            dbg(TRANSPORT_CHANNEL, "Removing socket %d\n",mySocketID);
                            call sockets.remove(mySocketID);
                            break;
                        
                        case(WAIT_ACK):
                            mySocket.state = WAIT_FINAL;

                            call sockets.insert(mySocketID, mySocket);
                            // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            // printSocket(mySocketID);

                            IDtoClose = mySocketID;
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
                    
                    { // NOW ENTERING: THE ACK SCOPE
                    tcpack ackPack;
                    mySocket.seq++;
                    makeTCPack(&ackPack, 0, 1, 0, 0, mySocket.dest.port, mySocket.srcPort, mySocket.dest.addr, TOS_NODE_ID, 1, mySocket.seq, mySocket.seqToRecv, noData());
                    call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                    // dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                    // logTCpack(&ackPack, TRANSPORT_CHANNEL);
    
                    call sockets.insert(mySocketID, mySocket);
                    // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                    // printSocket(mySocketID);
                    }
                    break;

                case(SYNC_ACK):
                    if(mySocket.state == SYNC_SENT){
                        tcpack ackPack;

                        mySocket.state = CONNECTED;
                        dbg(TRANSPORT_CHANNEL,"Connection Established for socket %d!\n",mySocketID);
                        mySocket.seqToRecv = incomingMsg.seq+1;

                        mySocket.seq++;
                        makeTCPack(&ackPack, 0, 1, 0, 0, mySocket.dest.port, mySocket.srcPort, mySocket.dest.addr, TOS_NODE_ID, 1, mySocket.seq, mySocket.seqToRecv, noData());
                        call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                        // dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                        // logTCpack(&ackPack, TRANSPORT_CHANNEL);

                        call sendDelay.startOneShot(mySocket.RTT);

                        call sockets.insert(mySocketID, mySocket);
                        // dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                        // printSocket(mySocketID);
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

                createSocket(&newSocket, SYNC_RCVD, incomingDestPort, incomingSrcPort, incomingMsg.src, incomingMsg.seq);

                newSocket.seq++;                
                makeTCPack(&syncackPack, 1, 1, 0, 0, newSocket.srcPort, newSocket.dest.port, newSocket.dest.addr, TOS_NODE_ID, 1, newSocket.seq, newSocket.seqToRecv, noData());
                call send.send(255, incomingMsg.src, PROTOCOL_TCP, (uint8_t*) &syncackPack);
                // dbg(TRANSPORT_CHANNEL, "Sent SYNCACK:\n");
                // logTCpack(&syncackPack, TRANSPORT_CHANNEL);

                call sockets.insert(mySocketID, newSocket);
                dbg(TRANSPORT_CHANNEL, "New Socket:\n");
                printSocket(mySocketID);
            }
            else{
                dbg(TRANSPORT_CHANNEL, "Nonsense flag OR Empty Port: %d. Dropping.\n",incomingDestPort);
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
        if(call ports.contains(portRequest) == TRUE){
            dbg(TRANSPORT_CHANNEL, "ERROR: Port %d already in use by PTL %d.\n",portRequest, call ports.get(portRequest));
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

        newSocket.seq++;
        makeTCPack(&syncPack, 1, 0, 0, 0, destPort, srcPort, dest, TOS_NODE_ID, 1, newSocket.seq, 0, noData());
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &syncPack);
        // dbg(TRANSPORT_CHANNEL, "Sent SYNC:\n");
        // logTCpack(&syncPack, TRANSPORT_CHANNEL);
        
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
        socket.seq++;
        call sockets.insert(IDtoClose, socket);

        makeTCPack(&finPack, 0, 0, 1, 0, socket.dest.port, socket.srcPort, socket.dest.addr, TOS_NODE_ID, 1, socket.seq, socket.seqToRecv, noData());
        call send.send(255, socket.dest.addr, PROTOCOL_TCP, (uint8_t*) &finPack);
        dbg(TRANSPORT_CHANNEL, "Sent FIN:\n");
        logTCpack(&finPack, TRANSPORT_CHANNEL);
        
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
            if(socket.nextToSend!=socket.nextToWrite){//need to switch to window based
                timestamp ts;
                length = (socket.nextToWrite-socket.nextToSend>tc_max_pld_len) ? tc_max_pld_len : (socket.nextToWrite-socket.nextToSend);
                socket.seq++;
                makeTCPack(&packet,0,0,0,length,
                            socket.dest.port,socket.srcPort,socket.dest.addr,TOS_NODE_ID,
                            (SOCKET_BUFFER_SIZE+socket.nextToRead-socket.nextExpected)%SOCKET_BUFFER_SIZE,
                            socket.seq,socket.seqToRecv,&(socket.sendBuff[socket.nextToSend]));
                call send.send(255,socket.dest.addr,PROTOCOL_TCP,(uint8_t*)&packet);
                dbg(TRANSPORT_CHANNEL,"Sent Seq %d with byte %d!\n",socket.seq,socket.nextToSend);
                makeTimeStamp(&ts,2*socket.RTT,socketID,socket.seq,socket.nextToSend);
                socket.nextToSend = (socket.nextToSend+length)%SOCKET_BUFFER_SIZE;
                call sockets.insert(socketID,socket);
                call tsQueue.enqueue(ts);
                if(!call tsTimer.isRunning()){
                    call tsTimer.startOneShot(timeoutTime);
                }
            }
            else{
                dbg(TRANSPORT_CHANNEL,"No data in sendBuffer of socket %d\n",socketID);
            }
        }
    }

    command error_t TinyController.write(uint32_t socketID, uint8_t* payload, uint8_t length){
        socket_store_t socket;
        if(call sockets.contains(socketID)){
            socket = call sockets.get(socketID);
            if(socket.state == CONNECTED){
                //may cause seg faults, double check exact byte math!
                if(SOCKET_BUFFER_SIZE-((SOCKET_BUFFER_SIZE + (socket.nextToSend-socket.nextToWrite))%SOCKET_BUFFER_SIZE)>=length){//if room in buffer including wrap around
                    if(socket.nextToWrite+length<SOCKET_BUFFER_SIZE){
                        memcpy(&(socket.sendBuff[socket.nextToWrite]),payload,length);
                    }
                    else{//buffer wrap around
                        uint8_t remaining = socket.nextToWrite+length-SOCKET_BUFFER_SIZE;
                        memcpy(&(socket.sendBuff[socket.nextToWrite]),payload,remaining);
                        memcpy(&(socket.sendBuff[0]),payload+remaining,length-remaining);
                    }
                    socket.nextToWrite = (socket.nextToWrite+length)%SOCKET_BUFFER_SIZE;
                    call sockets.insert(socketID,socket);
                    call sendQueue.enqueue(socketID);
                    post sendData();
                    return SUCCESS;
                }
                else{
                    dbg(TRANSPORT_CHANNEL,"Not enough room in sendbuffer. nextToSend: %d, nextToWrite: %d, room: %d, IS: %d\n",socket.nextToSend,socket.nextToWrite,SOCKET_BUFFER_SIZE-((SOCKET_BUFFER_SIZE + (socket.nextToSend-socket.nextToWrite))%SOCKET_BUFFER_SIZE),length);
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

    command uint8_t* TinyController.read(uint32_t socketID,uint8_t length){
        if(call sockets.contains(socketID)){
            uint8_t* output;
            readSocket = call sockets.get(socketID);
            output = &(readSocket.recvBuff[readSocket.nextToRead]);
            readSocket.nextToRead+=length;
            call sockets.insert(socketID,readSocket);
            return output;
        }
        else{
            dbg(TRANSPORT_CHANNEL,"Can't Read from nonexistent Socket %d\n",socketID);
            return 0;
        }
    }

    event void send.gotTCP(uint8_t* pkt){
        tcpack* incomingMsg = (tcpack*)pkt;
        memcpy(&storedMsg, incomingMsg, tc_pkt_len);
        call receiveQueue.enqueue(storedMsg);
        // dbg(TRANSPORT_CHANNEL, "Got TCpack\n");
        // logTCpack(incomingMsg, TRANSPORT_CHANNEL);
        post handlePack();
    }

    event void tsTimer.fired(){
        post checkTimeouts();
    }

    event void closeDelay.fired(){
        tcpack finPack;
        socket_store_t mySocket = call sockets.get(IDtoClose);

        mySocket.state = CLOSED;

        mySocket.seq++;
        makeTCPack(&finPack, 0, 0, 1, 0, mySocket.dest.port, mySocket.srcPort, mySocket.dest.addr, TOS_NODE_ID, 1, mySocket.seq, mySocket.seqToRecv, noData());
        call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &finPack);
        dbg(TRANSPORT_CHANNEL, "Sent FIN:\n");
        logTCpack(&finPack, TRANSPORT_CHANNEL);

        call sockets.insert(IDtoClose, mySocket);
        dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
        printSocket(IDtoClose);
    }

    //need to signal correct socket
    event void sendDelay.fired(){
        //This will eventually signal that data is ready to be sent, but for now I'm testing teardown.
        signal TinyController.connected(call sockets.getIndex(0));//all apps connected to tcp know about all sockets
        dbg(TRANSPORT_CHANNEL, "Ready to Send Data on socket %d!\n",call sockets.getIndex(0));
    }

    event void removeDelay.fired(){
        dbg(TRANSPORT_CHANNEL, "Removing socket %d\n",IDtoClose);
        call sockets.remove(IDtoClose);
    }

    void createSocket(socket_store_t* socket, uint8_t state, socket_port_t srcPort, socket_port_t destPort, uint8_t dest, uint16_t destSeq){
        socket_addr_t newDest;
        newDest.port = destPort;
        newDest.addr = dest;
        
        // socket->flag = flag;
        socket->state = state;
        socket->srcPort = srcPort;
        socket->dest = newDest;

        memset(socket->sendBuff,0,SOCKET_BUFFER_SIZE);
        socket->nextToWrite = 1; //Nothing has been written yet, it's a new socket!
        socket->lastAcked = 0; //Nothing has been acknowledged because nothing's sent, it's new!
        socket->nextToSend = 1; //Nothing has been sent, it's new!
        socket->seq = (call Random.rand16()) % (1<<16); //Randomize sequence number

        memset(socket->recvBuff,0,SOCKET_BUFFER_SIZE);
        socket->nextToRead = 0; //Nothing has been read yet, it's new!
        socket->lastRecv = 0; //This is the first time we've gotten something, let it have ID 0.
        socket->nextExpected = 0; //The next byte we expect will be byte 1!
        socket->seqToRecv = destSeq+1;  //This is the other's sequence number. (0 if we don't know)

        socket->RTT = 2000;
    }

    void makeTCPack(tcpack* pkt, uint8_t sync, uint8_t ack, uint8_t fin, uint8_t size, uint8_t dPort, uint8_t sPort, uint8_t dest, uint8_t src, uint8_t adWindow, uint16_t seq, uint16_t nextExp, uint8_t* data){
        // memset(pkt,0,tc_pkt_len);
        uint8_t flagField = 0;
        uint8_t portField = 0;

        //(left->right): 0000 0000
        //SYNC,ACK,FIN,size[5]
        flagField += sync<<7;
        flagField += ack<<6;
        flagField += fin<<5;
        flagField += (size & 31);
        pkt->flagsandsize = flagField;
        
        //(left->right): 0000 0000
        //destPort, srcPort
        portField += dPort<<4;
        portField += (sPort & 15);
        pkt->ports = portField;

        pkt->src = src;
        pkt->dest = dest;
        pkt->adWindow = adWindow;
        pkt->seq = seq;
        pkt->nextExp = nextExp;
        
        if(data!=0){
            memcpy(pkt->data, data, size);
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
            dbg(TRANSPORT_CHANNEL, "PRINTING SOCKET: ID: %d | State: %s | seq: %d | seqToRecv: %d | srcPort: %d | destPort: %d | src: %d | dest: %d\n",
                socketID,
                printedState,
                printedSocket.seq,
                printedSocket.seqToRecv,
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

    void makeTimeStamp(timestamp* ts, uint32_t timeout, uint32_t socketID,uint16_t seq, uint8_t byte){
        ts->expiration = call tsTimer.getNow()+timeout;
        ts->id = socketID;
        ts->seq = seq;
        ts->byte = byte;
    }

    uint8_t* noData(){
        uint8_t* nothing = 0;
        return nothing;
    }
}