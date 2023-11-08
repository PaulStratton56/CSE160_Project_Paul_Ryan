#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcpack.h"

module TinyControllerP{
    provides interface TinyController;

    uses interface Waysender as send;
    uses interface PacketHandler;

    uses interface Hashmap<port_t> as ports;
    uses interface Hashmap<socket_store_t> as sockets;

    uses interface Timer<TMilli> as sendDelay;

    uses interface Random;
}

implementation{
    uint16_t TCseq = 0;
    tcpack storedMsg;

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

            switch(incomingFlags){
                case(SYNC):
                    dbg(TRANSPORT_CHANNEL, "SYNC->Crash Detection.\n");
                    break;
                case(ACK):
                    if(mySocket.seqToRecv != storedMsg.seq){
                        dbg(TRANSPORT_CHANNEL, "BAD_SEQ: Expected %d, got %d\n",mySocket.seqToRecv, storedMsg.seq);
                    }
                    else{
                        switch(mySocket.state){
                            case(SYNC_RCVD):
                                mySocket.state = CONNECTED;
                                mySocket.seqToRecv++;

                                call sockets.insert(mySocketID, mySocket);
                                dbg(TRANSPORT_CHANNEL, "Updated Socket:\n");
                                printSocket(mySocketID);

                                break;

                            case(CONNECTED):
                                dbg(TRANSPORT_CHANNEL, "Passing data to buffer.\n");
                                break;

                            default:
                                dbg(TRANSPORT_CHANNEL, "Unexpected ACK.\n");
                                break;
                        }
                    }
                    break;
                case(FIN):
                    dbg(TRANSPORT_CHANNEL, "FIN received.\n");
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
                dbg(TRANSPORT_CHANNEL, "Empty Port: %d. Dropping.\n",incomingDestPort);
            }
        }
    }  

    command error_t TinyController.getPort(uint8_t portRequest, socket_t ptcl){
        if(call ports.contains(portRequest) == TRUE){
            // dbg(TRANSPORT_CHANNEL, "ERROR: Port %d already in use by ptcl %d.\n",portRequest, call ports.get(portRequest));
            return FAIL;
        }
        else{
            call ports.insert((uint32_t)portRequest, ptcl);
            dbg(TRANSPORT_CHANNEL, "PTL %d on Port %d\n",ptcl, portRequest);
            return SUCCESS;
        }
    }

    command void TinyController.requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        socket_store_t newSocket;
        tcpack syncPack;
        uint32_t socketID = getSocketID(dest, destPort, srcPort);

        createSocket(&newSocket, SYNC_SENT, srcPort, destPort, dest, 0);

        newSocket.seq++;
        makeTCPack(&syncPack, 1, 0, 0, 0, destPort, srcPort, dest, TOS_NODE_ID, 1, newSocket.seq, 0, noData());
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &syncPack);
        dbg(TRANSPORT_CHANNEL, "Sent SYNC:\n");
        logTCpack(&syncPack, TRANSPORT_CHANNEL);
        
        call sockets.insert(socketID, newSocket);
        dbg(TRANSPORT_CHANNEL, "New Socket:\n");
        printSocket(socketID);
    }

    // command bool send(uint8_t* payload){


    // }

    // command uint8_t* receive(){

    
    // }

    event void send.gotTCP(uint8_t* pkt){
        tcpack* incomingMsg = (tcpack*)pkt;
        dbg(TRANSPORT_CHANNEL, "Got TCpack\n");
        memcpy(&storedMsg, incomingMsg, tc_pkt_len);
        // logTCpack(incomingMsg, TRANSPORT_CHANNEL);
        post handlePack();
    }

    event void sendDelay.fired(){
        //Nothing
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
            dbg(TRANSPORT_CHANNEL, "SocketID: %d | State: %d | srcPort: %d | destPort: %d | src: %d | dest: %d | seq: %d | seqToRecv: %d\n",
                socketID,
                printedSocket.state,
                printedSocket.srcPort,
                printedSocket.dest.port,
                TOS_NODE_ID,
                printedSocket.dest.addr,
                printedSocket.seq,
                printedSocket.seqToRecv
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

    event void PacketHandler.gotPing(uint8_t* _){};
    event void PacketHandler.gotflood(uint8_t* _){};
    event void PacketHandler.gotRouted(uint8_t* _){};

}