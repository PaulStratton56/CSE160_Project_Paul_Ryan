#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/ndpack.h"
#include "../../includes/protocol.h"

/*
== PacketHandler ==
Provides a module for Node to quickly pass an incoming packet to.
Takes an incoming 'pack' and checks protocol to signal to higher level modules.
Assumes that the payload is already fragmented to conform to fit in a 'pack''s payload.'
*/
module PacketHandlerP{
    provides interface PacketHandler;

    uses interface SimpleSend as send;
}

implementation{

    void makePack(pack *pkg, uint16_t src, uint16_t dst, uint16_t ptl, uint8_t* pld);

    command error_t PacketHandler.handle(pack* incomingMsg){
        //Strip SimpleSend header by getting 'payload'
        uint8_t* pkt = (uint8_t*)(((pack*)incomingMsg)->pld);
        //Check the SimpleSend protocol to pass to higher level modules.
        switch(incomingMsg->ptl){
            case PROTOCOL_NEIGHBOR:
                signal PacketHandler.gotPing(pkt);
                break;
            case PROTOCOL_FLOOD:
                signal PacketHandler.gotflood(pkt);
                break;
            case PROTOCOL_ROUTING:
                signal PacketHandler.gotRouted(pkt);
                break;
        }  
        return SUCCESS;
    }

    command void PacketHandler.send(uint8_t src, uint8_t dst, uint8_t ptl, uint8_t* pld){
        pack pkt;
        makePack(&pkt, src, dst, ptl, pld);

        if(dst == (uint8_t)AM_BROADCAST_ADDR){
            call send.send(pkt, AM_BROADCAST_ADDR);
        }
        else{
            call send.send(pkt, dst);
        }
        
    }

    void makePack(pack *pkg, uint16_t src, uint16_t dst, uint16_t ptl, uint8_t* pld){
        memset(pkg,0,pkt_len);
        pkg->src = src;
        pkg->dst = dst;
        pkg->ptl = ptl;
        memcpy(pkg->pld, pld, pkt_max_pld_len);
    }

}