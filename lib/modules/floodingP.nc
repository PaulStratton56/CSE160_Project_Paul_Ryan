#include "../../includes/packet.h"

 module floodingP{
    provides interface flooding;

    uses interface SimpleSend as waveSend;
    uses interface Hashmap<uint16_t> as packets;
    uses interface neighborDiscovery as neighborhood;
    uses interface PacketHandler;
}

implementation{
    pack myWave;
    command void flooding.wave(){
        dbg(FLOODING_CHANNEL,"TSUNAMI!\n");
    }
    void broadsend(){
        pack wave;
        int i = 0;
        uint32_t* myNeighbors = call neighborhood.getNeighbors();
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        call waveSend.makePack(&wave,myWave.src,TOS_NODE_ID,myWave.TTL-1,PROTOCOL_FLOOD,myWave.seq,myWave.payload,PACKET_MAX_PAYLOAD_SIZE);
        if(!call neighborhood.excessNeighbors()){
            for(i=0;i<numNeighbors;i++){
                if(myNeighbors[i]!=(uint32_t)myWave.dest){
                    dbg(FLOODING_CHANNEL,"Propagating Flood Message: '%s' sent to me by %d. Sending to %d\n",myWave.payload, myWave.dest,myNeighbors[i]);
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
        if(!call packets.contains(myWave.src) || call packets.get(myWave.src)<myWave.seq){
            call packets.insert(myWave.src,myWave.seq);
            if(myWave.TTL>0){
                call neighborhood.printMyNeighbors();
                broadsend();
            }
            else{
                dbg(FLOODING_CHANNEL,"Dead Packet. Won't Propagate\n");
            }
        }
        else{
            dbg(FLOODING_CHANNEL,"Already propagated %s. Duplicate came from %hhu\n",myWave.payload,myWave.dest);
        }
    
        //use src for original source, dest for sender id, since dest doesn't matter for flooding
        //if should, get neighborhood
        //for every neighbor, except people already known to have it, send alertPacket to them
        //if full hashmap, switch to broadcast
        //decrement ttl
    }
    
    event void PacketHandler.gotflood(pack* wave){
        memcpy(&myWave,wave,28);
        post flood();
    }
    event void PacketHandler.gotPingRequest(pack* _){}
    event void PacketHandler.gotPingReply(pack* _){}

}