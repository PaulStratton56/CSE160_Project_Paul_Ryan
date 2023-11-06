#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/tcpack.h"

module TinyControllerP{
    provides interface TinyController;

    uses interface Waysender as send;
    uses interface PacketHandler;
    uses interface Hashmap<port_t> as ports;
    uses interface Hashmap<socket_store_t*> as sockets;
    uses interface Random;
}

implementation{
    uint16_t TCseq = 0;

    void createSocket(
        socket_store_t*   socket, 
        uint8_t           flag, 
        enum socket_state state, 
        socket_port_t     srcPort, 
        socket_port_t     destPort,
        uint8_t           dest,
        uint16_t          destSeq
    );

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
        uint16_t ackseq,
        uint8_t* data
    );

    command error_t TinyController.getPort(uint8_t portRequest, socket_t ptcl){
        if(call ports.contains(portRequest) == TRUE){
            dbg(TRANSPORT_CHANNEL, "ERROR: Port %d already in use by ptcl %d.\n",portRequest, call ports.get(portRequest));
            dbg(TRANSPORT_CHANNEL, "size: %d", call ports.size());
            return FAIL;
        }
        else if(call ports.size() == call ports.maxSize()){
            dbg(TRANSPORT_CHANNEL, "ERROR: Maximum Port Usage.\n", portRequest);
            return FAIL;
        }
        else{
            call ports.insert((uint32_t)portRequest, ptcl);
            dbg(TRANSPORT_CHANNEL, "Port %d allocated to protocol %d\n",portRequest, ptcl);
            return SUCCESS;
        }
    }

    command void TinyController.requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort){
        socket_t socketID = (dest<<3) + (TOS_NODE_ID<<3) + (destPort<<4) + (srcPort<<4);
        socket_store_t newSocket;
        tcpack synPack;
        uint8_t* noData = 0;
        createSocket(&newSocket, 0, SYN_SENT, srcPort, destPort, dest, 0);
        call sockets.insert(socketID, &newSocket);
        
        makeTCPack(&synPack, 1, 0, 0, 0, destPort, srcPort, dest, TOS_NODE_ID, 0, newSocket.lastSent, 0, noData);
        call send.send(255, dest, PROTOCOL_TCP, (uint8_t*) &synPack);
        dbg(TRANSPORT_CHANNEL, "Sent TCPack.\n");
        logTCpack(&synPack, TRANSPORT_CHANNEL);

    }

    // command bool send(uint8_t* payload){


    // }

    // command uint8_t* receive(){

    
    // }

    event void send.gotTCP(uint8_t* pkt){
        tcpack* incomingMsg = (tcpack*)pkt;
        logTCpack(incomingMsg, TRANSPORT_CHANNEL);
    }

    void createSocket(socket_store_t* socket, uint8_t flag, enum socket_state state, socket_port_t srcPort, socket_port_t destPort, uint8_t dest, uint16_t destSeq){
        socket_addr_t newDest;
        uint16_t newSeq = (call Random.rand16()) % (1<<16);
        newDest.port = destPort;
        newDest.addr = dest;
        
        socket->flag = flag;
        socket->state = state;
        socket->src = srcPort;
        socket->dest = newDest;

        socket->lastWritten = newSeq;
        socket->lastAck = newSeq;
        socket->lastSent = newSeq;

        socket->lastRead = destSeq;
        socket->lastRcvd = destSeq;
        socket->nextExpected = destSeq+1;
    }

    void makeTCPack(tcpack* pkt, uint8_t sync, uint8_t ack, uint8_t fin, uint8_t size, uint8_t dPort, uint8_t sPort, uint8_t dest, uint8_t src, uint8_t adWindow, uint16_t seq, uint16_t ackseq, uint8_t* data){

        uint8_t flagField = 0;
        uint8_t portField = 0;

        flagField += sync<<7;
        flagField += ack<<6;
        flagField += fin<<5;
        flagField += (size & 31);
        pkt->flagsandsize = flagField;
        
        portField += dPort<<4;
        portField += (sPort & 15);
        pkt->ports = portField;

        pkt->src = src;
        pkt->dest = dest;
        pkt->adWindow = adWindow;
        pkt->seq = seq;
        pkt->ackseq = ackseq;
        
        memcpy(pkt->data, data, size);
    }

    event void PacketHandler.gotPing(uint8_t* _){};
    event void PacketHandler.gotflood(uint8_t* _){};
    event void PacketHandler.gotRouted(uint8_t* _){};

}