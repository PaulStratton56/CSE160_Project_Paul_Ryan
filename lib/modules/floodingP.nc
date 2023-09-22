#include "../../includes/packet.h"

 module floodingP{
    provides interface flooding;

    uses interface SimpleSend as waveSend;
    uses interface Hashmap<uint16_t> as packets;
    uses interface neighborDiscovery as neighborhood;
}

implementation{
    command void flooding.wave(){
        dbg(FLOODING_CHANNEL,"TSUNAMI!\n");
    }
    void broadsend(pack* alertPacket){
        pack wave;
        int i = 0;
        uint32_t* myNeighbors = call neighborhood.getNeighbors();
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        call waveSend.makePack(&wave,alertPacket->src,TOS_NODE_ID,alertPacket->TTL-1,PROTOCOL_FLOOD,alertPacket->seq,alertPacket->payload,PACKET_MAX_PAYLOAD_SIZE);
        if(!call neighborhood.excessNeighbors()){
            for(i=0;i<numNeighbors;i++){
                if(myNeighbors[i]!=(uint32_t)alertPacket->dest){
                    dbg(FLOODING_CHANNEL,"Propagating Flood Message: '%s' sent to me by %d. Sending to %d\n",alertPacket->payload, alertPacket->dest,myNeighbors[i]);
                    call waveSend.send(wave,myNeighbors[i]);
                }
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Max Neighbors, so broadcasting flood wave...\n");
            call waveSend.send(wave,AM_BROADCAST_ADDR);
        }
    }
    command void flooding.flood(pack* alertPacket){
        uint16_t source = alertPacket->src;
        //check if should forward packet
        if(!call packets.contains(source) || call packets.get(source)<alertPacket->seq){
            call packets.insert(source,alertPacket->seq);
            if(alertPacket->TTL>0){
                call neighborhood.printMyNeighbors();
                broadsend(alertPacket);
            }
            else{
                dbg(FLOODING_CHANNEL,"Dead Packet. Won't Propagate\n");
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Already propagated %s. Duplicate came from %hhu\n",alertPacket->payload,alertPacket->dest);
        }
        //use src for original source, dest for sender id, since dest doesn't matter for flooding
        //if should, get neighborhood
        //for every neighbor, except people already known to have it, send alertPacket to them
        //if full hashmap, switch to broadcast
        //decrement ttl
    }
}