#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/protocol.h"

 module floodingP{
    provides interface flooding;

    uses interface SimpleSend as waveSend;
    uses interface Hashmap<uint16_t> as packets;
    uses interface neighborDiscovery as neighborhood;
}

implementation{

    void makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);

    command void flooding.wave(){
        dbg(FLOODING_CHANNEL,"TSUNAMI!\n");
    }
    
    void broadsend(floodpack* packet){
        pack wave;
        int i = 0;
        uint32_t* myNeighbors = call neighborhood.getNeighbors();
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        call waveSend.makePack(&wave,packet->original_src,packet->prev_src,packet->ttl,PROTOCOL_FLOOD,packet->seq,(uint8_t*) packet,PACKET_MAX_PAYLOAD_SIZE);
        if(!call neighborhood.excessNeighbors()){
            for(i=0;i<numNeighbors;i++){
                if(myNeighbors[i]!=(uint32_t)packet->prev_src){
                    dbg(FLOODING_CHANNEL,"Propagating Flood Message: '%s' sent to me by %d. Sending to %d\n",(char*) packet->payload, packet->prev_src, myNeighbors[i]);
                    call waveSend.send(wave,myNeighbors[i]);
                }
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Max Neighbors, so broadcasting flood wave...\n");
            call waveSend.send(wave,AM_BROADCAST_ADDR);
        }
    }
    command void flooding.flood(uint8_t* alertPacket){
        floodpack* packet = (floodpack*) alertPacket;
        floodpack newPack;

        //check if should forward packet
        if(!call packets.contains(packet->original_src) || call packets.get(packet->original_src)<packet->seq){
            call packets.insert(packet->original_src,packet->seq);
            if(packet->ttl>0){
                call neighborhood.printMyNeighbors();
                call flooding.makeFloodPack(&newPack, packet->original_src, TOS_NODE_ID, packet->seq, (packet->ttl-1), packet->protocol, (uint8_t*) packet->payload);
                broadsend(&newPack);
            }
            else{
                dbg(FLOODING_CHANNEL,"Dead Packet. Won't Propagate\n");
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Already propagated %s. Duplicate came from %hhu\n",(char*) packet->payload,packet->prev_src);
        }
        //use src for original source, dest for sender id, since dest doesn't matter for flooding
        //if should, get neighborhood
        //for every neighbor, except people already known to have it, send alertPacket to them
        //if full hashmap, switch to broadcast
        //decrement ttl
    }

    command error_t flooding.makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload){
        packet->original_src = o_src;
        packet->prev_src = p_src;
        packet->seq = seq;
        packet->ttl = ttl;
        packet->protocol = protocol;
        memcpy(packet->payload, payload, FLOOD_PACKET_MAX_PAYLOAD_SIZE);
        return SUCCESS;
    }

}