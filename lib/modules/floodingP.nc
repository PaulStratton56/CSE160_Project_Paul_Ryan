#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/protocol.h"

 module floodingP{
    provides interface flooding;

    uses interface SimpleSend as waveSend;
    uses interface Hashmap<uint16_t> as packets;
    uses interface neighborDiscovery as neighborhood;
    uses interface PacketHandler;
}

implementation{
    floodpack myWave;
    void makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);
    
    void broadsend(){
        pack wave;
        int i = 0;
        uint32_t* myNeighbors = call neighborhood.getNeighbors();
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        uint16_t prevNode = myWave.prev_src;

        myWave.prev_src = TOS_NODE_ID;
        myWave.ttl -= 1;
        
        call waveSend.makePack(&wave,myWave.original_src,myWave.prev_src,myWave.ttl,PROTOCOL_FLOOD,myWave.seq,(uint8_t*) &myWave,PACKET_MAX_PAYLOAD_SIZE);
        
        if(!call neighborhood.excessNeighbors()){
            for(i=0;i<numNeighbors;i++){
                if(myNeighbors[i]!=(uint32_t)prevNode){
                    dbg(FLOODING_CHANNEL,"Propagating Flood Message: '%s' sent to me by %d. Sending to %d\n", (char*) myWave.payload, prevNode, myNeighbors[i]);
                    call waveSend.send(wave,myNeighbors[i]);
                }
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Max Neighbors, so broadcasting flood wave...\n");
            call waveSend.send(wave,AM_BROADCAST_ADDR);
        }
    }

    task void flood(){
        //check if should forward packet
        if(!call packets.contains(myWave.original_src) || call packets.get(myWave.original_src)<myWave.seq){
            call packets.insert(myWave.original_src,myWave.seq);

            if(myWave.ttl>0){
                call neighborhood.printMyNeighbors();
                broadsend();
            }
            else{
                dbg(FLOODING_CHANNEL,"Dead Packet. Won't Propagate\n");
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Already propagated '%s'. Duplicate came from %hhu\n",(char*) myWave.payload,myWave.prev_src);
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
    
    event void PacketHandler.gotflood(uint8_t* wave){
        memcpy(&myWave,wave,20);
        post flood();
    }
    
    event void PacketHandler.gotPing(uint8_t* _){}

}