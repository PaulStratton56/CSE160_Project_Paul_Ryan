#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"
#include <string.h>
#include <stdio.h>
module neighborDiscoveryP{
    provides interface neighborDiscovery;
    
    uses interface SimpleSend as pingSend;
    uses interface Timer<TMilli> as pingTimer;
    uses interface Hashmap<linkquality> as neighborhood;
    uses interface PacketHandler;
}

implementation{
    ndpack myPing;
    ndpack mypingReply;
    ndpack incomingNDpack;
    pack myPack;
    uint32_t* myNeighbors;
    float decayRate=.25;
    float allowedQuality=.4;

    task void ping(){
        myPing.seq += 1;
        dbg(NEIGHBOR_CHANNEL,"Hello? Who's There?\n");
        call pingSend.makePack(&myPack,TOS_NODE_ID,AM_BROADCAST_ADDR,0,PROTOCOL_NEIGHBOR,myPing.seq,(uint8_t*) &myPing,PACKET_MAX_PAYLOAD_SIZE);
        call pingSend.send(myPack,AM_BROADCAST_ADDR);
        call pingTimer.startOneShot(4000);
    }

    command void neighborDiscovery.onBoot(){
        char sendPayload[] = "Who's There?";
        char replyPayload[] = "I'm here!";

        call neighborDiscovery.makeNeighborPack(&myPing, TOS_NODE_ID, 0, PROTOCOL_PING, (uint8_t*) sendPayload);
        call neighborDiscovery.makeNeighborPack(&mypingReply, TOS_NODE_ID, 0, PROTOCOL_PINGREPLY, (uint8_t*) replyPayload);
        
        post ping();
    }

    task void updateLinks(){
        uint16_t i=0;
        linkquality status;
        uint16_t numNeighbors = call neighborhood.size();
        myNeighbors = call neighborhood.getKeys();
        while(i<numNeighbors){
            if(call neighborhood.contains(myNeighbors[i])){
                status=call neighborhood.get(myNeighbors[i]);
                if(!status.recent){
                    status.quality = (1-decayRate)*status.quality;
                    dbg(NEIGHBOR_CHANNEL,"Missed pingReply from %d, quality is now %.4f\n",myNeighbors[i],status.quality);
                }
                if(status.quality<allowedQuality){
                    dbg(NEIGHBOR_CHANNEL,"Removing %d,%.4f from my list for being less than %.4f.\n",myNeighbors[i],status.quality,allowedQuality);
                    call neighborhood.remove(myNeighbors[i]);
                    numNeighbors -= 1;
                    i--;
                }
                else{
                    status.recent=FALSE;
                    call neighborhood.insert(myNeighbors[i],status);
                }
            }
            i++;
        }
        post ping();
    }
    
    event void pingTimer.fired(){
        post updateLinks();
    }

    task void respondtoPingRequest(){       
        dbg(NEIGHBOR_CHANNEL,"Responding to Ping Request from %hhu\n",incomingNDpack.src);

        mypingReply.seq = incomingNDpack.seq;
        call pingSend.makePack(&myPack,TOS_NODE_ID,incomingNDpack.src,0,PROTOCOL_NEIGHBOR,mypingReply.seq,(uint8_t*) &mypingReply,PACKET_MAX_PAYLOAD_SIZE);
        call pingSend.send(myPack,myPack.dest);
    }

    task void respondtoPingReply(){
        linkquality status;
        status.quality=1;
        if(call neighborhood.contains(incomingNDpack.src)){
            status = call neighborhood.get(incomingNDpack.src);
            status.quality = decayRate+(1-decayRate)*status.quality;
            dbg(NEIGHBOR_CHANNEL,"Got ping reply from %d, quality is now %.4f\n",incomingNDpack.src,status.quality);
        }
        else{
            dbg(NEIGHBOR_CHANNEL,"Adding new neighbor %hhu...\n",incomingNDpack.src);
        }
        status.recent=TRUE;
        call neighborhood.insert(incomingNDpack.src,status);
    }

    event void PacketHandler.gotPing(uint8_t* packet){
        memcpy((uint8_t*) &incomingNDpack, packet,20);
        if(incomingNDpack.protocol == PROTOCOL_PING){
            post respondtoPingRequest();
        }
        else if(myPing.protocol == PROTOCOL_PINGREPLY){
            post respondtoPingReply();
        }
        else{
            dbg(GENERAL_CHANNEL,"Packet Handler Error: Incorrectly received PROTOCOL_NEIGHBOR packet payload\n");
        }
    }

    event void PacketHandler.gotflood(uint8_t* _){}

    command uint32_t* neighborDiscovery.getNeighbors(){
        return call neighborhood.getKeys();
    }
    command uint16_t neighborDiscovery.numNeighbors(){
        return call neighborhood.size();
    }
    command bool neighborDiscovery.excessNeighbors(){
        return call neighborhood.size()==call neighborhood.maxSize();
    }
    command void neighborDiscovery.printMyNeighbors(){//yuck!
        uint16_t size = call neighborhood.size();
        char sNeighbor[] = "";
        char buffer[3*size];
        uint32_t neighbor = 0;
        int i=0;
        int bufferIndex=0;
        myNeighbors = call neighborhood.getKeys();
        for (i=0;i<size;i++){
            neighbor = myNeighbors[i];
            sprintf(sNeighbor,"%u", (unsigned int)neighbor);
            buffer[bufferIndex]=sNeighbor[0];
            buffer[bufferIndex+1]=',';
            buffer[bufferIndex+2]=' ';
            bufferIndex+=3;
        }
        buffer[bufferIndex-2]='\00';//dont need last , and space
        dbg(NEIGHBOR_CHANNEL,"My Neighbors are: %s\n",buffer);
    }

    command error_t neighborDiscovery.makeNeighborPack(ndpack* packet, uint16_t src, uint8_t seq, uint8_t protocol, uint8_t* payload){
        packet->src = src;
        packet->seq = seq;
        packet->protocol = protocol;
        
        memcpy(packet->payload, payload, ND_PACKET_MAX_PAYLOAD_SIZE);
        return SUCCESS;
    }

}
