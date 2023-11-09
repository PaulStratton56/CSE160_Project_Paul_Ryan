#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcpack.h"

module TinyControllerP{
    provides interface TinyController;

    uses interface Waysender as send;
    
    uses interface Hashmap<port_t> as ports;
    uses interface Hashmap<socket_store_t> as sockets;

    uses interface Timer<TMilli> as sendDelay;
    uses interface Timer<TMilli> as removeDelay; // Timer to remove the socket after moving to WAIT_FINAL state.
    uses interface Timer<TMilli> as closeDelay; // Dummy timer to signal the app has closed to move from CLOSING to CLOSED.

    uses interface Random;
}

implementation{
    tcpack storedMsg;
    uint32_t IDtoClose;

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

    //The brunt of the work - based on a connection state and flags, do something with the inbound packet.
    task void handlePack(){
        uint8_t incomingFlags = (storedMsg.flagsandsize & 224)>>5;
        uint8_t incomingSrcPort = ((storedMsg.ports) & 240)>>4;
        uint8_t incomingDestPort = (storedMsg.ports) & 15;
        
        uint32_t mySocketID = getSocketID(storedMsg.src, incomingSrcPort, incomingDestPort);

        if(call sockets.contains(mySocketID)){
            socket_store_t mySocket = call sockets.get(mySocketID);
            if(mySocket.seqToRecv != storedMsg.seq && mySocket.state != SYNC_SENT){
                dbg(TRANSPORT_CHANNEL, "BAD_SEQ: Expected %d, got %d\n",mySocket.seqToRecv, storedMsg.seq);
            }
            else{
                mySocket.seqToRecv++;
            }

            switch(incomingFlags){
                case(SYNC):
                    //More logic required to detect a crash, etc.
                    dbg(TRANSPORT_CHANNEL, "SYNC->Crash Detection.\n");
                    break;
                case(ACK):
                    switch(mySocket.state){
                        case(SYNC_RCVD):
                            //Signal that data is probably inbound!
                            mySocket.state = CONNECTED;

                            call sockets.insert(mySocketID, mySocket);
                            dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            printSocket(mySocketID);
                            break;

                        case(CONNECTED):
                            //Received an ack to our data, update window, etc.
                            break;

                        case(WAIT_ACKFIN):
                            mySocket.state = WAIT_FIN;

                            call sockets.insert(mySocketID, mySocket);
                            dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            printSocket(mySocketID);
                            break;
                        
                        case(CLOSED):
                            dbg(TRANSPORT_CHANNEL, "Removing socket %d\n",mySocketID);
                            call sockets.remove(mySocketID);
                            break;
                        
                        case(WAIT_ACK):
                            mySocket.state = WAIT_FINAL;

                            call sockets.insert(mySocketID, mySocket);
                            dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                            printSocket(mySocketID);

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
                    
                    { // NOW ENTERING: THE A C K S C O P E
                    tcpack ackPack;
                    mySocket.seq++;
                    makeTCPack(&ackPack, 0, 1, 0, 0, mySocket.dest.port, mySocket.srcPort, mySocket.dest.addr, TOS_NODE_ID, 1, mySocket.seq, mySocket.seqToRecv, noData());
                    call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                    dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                    logTCpack(&ackPack, TRANSPORT_CHANNEL);
    
                    call sockets.insert(mySocketID, mySocket);
                    dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                    printSocket(mySocketID);
                    }
                    break;

                case(SYNC_ACK):
                    if(mySocket.state == SYNC_SENT){
                        tcpack ackPack;

                        mySocket.state = CONNECTED;
                        mySocket.seqToRecv = storedMsg.seq+1;

                        mySocket.seq++;
                        makeTCPack(&ackPack, 0, 1, 0, 0, mySocket.dest.port, mySocket.srcPort, mySocket.dest.addr, TOS_NODE_ID, 1, mySocket.seq, mySocket.seqToRecv, noData());
                        call send.send(255, mySocket.dest.addr, PROTOCOL_TCP, (uint8_t*) &ackPack);
                        dbg(TRANSPORT_CHANNEL, "Sent ACK:\n");
                        logTCpack(&ackPack, TRANSPORT_CHANNEL);

                        call sendDelay.startOneShot(mySocket.RTT);

                        call sockets.insert(mySocketID, mySocket);
                        dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                        printSocket(mySocketID);
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

                createSocket(&newSocket, SYNC_RCVD, incomingDestPort, incomingSrcPort, storedMsg.src, storedMsg.seq);

                newSocket.seq++;                
                makeTCPack(&syncackPack, 1, 1, 0, 0, newSocket.srcPort, newSocket.dest.port, newSocket.dest.addr, TOS_NODE_ID, 1, newSocket.seq, newSocket.seqToRecv, noData());
                call send.send(255, storedMsg.src, PROTOCOL_TCP, (uint8_t*) &syncackPack);
                dbg(TRANSPORT_CHANNEL, "Sent SYNCACK:\n");
                logTCpack(&syncackPack, TRANSPORT_CHANNEL);

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
    command error_t TinyController.requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        socket_store_t newSocket;
        tcpack syncPack;
        uint32_t socketID;

        if(!call ports.contains(srcPort)){
            dbg(TRANSPORT_CHANNEL, "ERROR: cannot make socket with port %d (unused).\n",srcPort);
            return FAIL;
        }

        socketID = getSocketID(dest, destPort, srcPort);

        createSocket(&newSocket, SYNC_SENT, srcPort, destPort, dest, 0);

        newSocket.seq++;
        makeTCPack(&syncPack, 1, 0, 0, 0, destPort, srcPort, dest, TOS_NODE_ID, 1, newSocket.seq, 0, noData());
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &syncPack);
        dbg(TRANSPORT_CHANNEL, "Sent SYNC:\n");
        logTCpack(&syncPack, TRANSPORT_CHANNEL);
        
        call sockets.insert(socketID, newSocket);
        dbg(TRANSPORT_CHANNEL, "New Socket:\n");
        printSocket(socketID);
        return SUCCESS;
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
    command error_t TinyController.closeConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        uint32_t socketID = getSocketID(dest, destPort, srcPort);
        socket_store_t socket;
        tcpack finPack;
        
        if(!call sockets.contains(socketID)){
            dbg(TRANSPORT_CHANNEL, "ERROR: Cannot close socket ID %d (DNE).\n",socketID);
            return FAIL;
        }

        socket = call sockets.get(socketID);
        
        socket.state = WAIT_ACKFIN;

        socket.seq++;
        makeTCPack(&finPack, 0, 0, 1, 0, socket.dest.port, socket.srcPort, socket.dest.addr, TOS_NODE_ID, 1, socket.seq, socket.seqToRecv, noData());
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &finPack);
        dbg(TRANSPORT_CHANNEL, "Sent FIN:\n");
        logTCpack(&finPack, TRANSPORT_CHANNEL);
        
        call sockets.insert(socketID, socket);
        dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
        printSocket(socketID);

        return SUCCESS;
    }

    // command bool send(uint8_t* payload){


    // }

    // command uint8_t* receive(){

    
    // }

    event void send.gotTCP(uint8_t* pkt){
        tcpack* incomingMsg = (tcpack*)pkt;
        dbg(TRANSPORT_CHANNEL, "Got TCpack\n");
        memcpy(&storedMsg, incomingMsg, tc_pkt_len);
        logTCpack(incomingMsg, TRANSPORT_CHANNEL);
        post handlePack();
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

    event void sendDelay.fired(){
        //This will eventually signal that data is ready to be sent, but for now I'm testing teardown.
        dbg(TRANSPORT_CHANNEL, "Ready to Send Data!\n");
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

        socket->nextToWrite = 0; //Nothing has been written yet, it's a new socket!
        socket->lastAcked = 0; //Nothing has been acknowledged because nothing's sent, it's new!
        socket->nextToSend = 0; //Nothing has been sent, it's new!
        socket->seq = (call Random.rand16()) % (1<<16); //Randomize sequence number

        socket->nextToRead = 0; //Nothing has been read yet, it's new!
        socket->lastRecv = 0; //This is the first time we've gotten something, let it have ID 0.
        socket->nextExpected = 1; //The next byte we expect will be byte 1!
        socket->seqToRecv = destSeq+1;  //This is the other's sequence number. (0 if we don't know)
    }

    void makeTCPack(tcpack* pkt, uint8_t sync, uint8_t ack, uint8_t fin, uint8_t size, uint8_t dPort, uint8_t sPort, uint8_t dest, uint8_t src, uint8_t adWindow, uint16_t seq, uint16_t nextExp, uint8_t* data){

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
        
        memcpy(pkt->data, data, size);
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
            dbg(TRANSPORT_CHANNEL, "ID: %d | State: %s | seq: %d | seqToRecv: %d | srcPort: %d | destPort: %d | src: %d | dest: %d\n",
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
        return (dest<<4) + (TOS_NODE_ID<<8) + (destPort<<12) + (srcPort<<16);
    }

    uint8_t* noData(){
        uint8_t* nothing = 0;
        return nothing;
    }
}