#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include <string.h>
#include <stdio.h>
module neighborDiscoveryP{
    provides interface neighborDiscovery;
    
    uses interface SimpleSend as pingSend;
    uses interface Timer<TMilli> as pingTimer;
    uses interface Hashmap<uint16_t> as neighborhood;
    uses interface PacketHandler;
}

implementation{
    pack myPing;
    pack mypingReply;
    pack myPack;
    uint32_t* myNeighbors;
    task void ping(){
        ndpack* innerPack = (ndpack*) myPing.payload;
        innerPack->seq += 1;
        dbg(NEIGHBOR_CHANNEL,"Hello? Who's There?\n");
        call pingSend.send(myPing,AM_BROADCAST_ADDR);
        call pingTimer.startOneShot(2000);
    }

    command void neighborDiscovery.onBoot(){
        ndpack innerSendPack;
        ndpack innerReplyPack;
        char sendPayload[] = "Who's There?";
        char replyPayload[] = "I'm here!";

        call neighborDiscovery.makeNeighborPack(&innerSendPack, TOS_NODE_ID, 0, PROTOCOL_PING, (uint8_t*) sendPayload);
        call pingSend.makePack(&myPing, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_NEIGHBOR, 0, (uint8_t*) &innerSendPack, PACKET_MAX_PAYLOAD_SIZE);

        call neighborDiscovery.makeNeighborPack(&innerReplyPack, TOS_NODE_ID, 0, PROTOCOL_PINGREPLY, (uint8_t*) replyPayload);
        call pingSend.makePack(&mypingReply, TOS_NODE_ID, 0, 0, PROTOCOL_NEIGHBOR, 0, (uint8_t*) &innerReplyPack, PACKET_MAX_PAYLOAD_SIZE);
        
        post ping();
    }

    event void pingTimer.fired(){
        uint16_t i=0;
        uint16_t seq;
        uint8_t acceptableMisses=3;
        uint16_t numNeighbors = call neighborhood.size();
        ndpack* innerPack = (ndpack*) myPing.payload;
        myNeighbors = call neighborhood.getKeys(); 
        //could do more analysis on data, especially if stored most recent data per node
        //could do this with hashmap of linked list, using last k interactions 
        //exponential importance model (more recent more important than a while ago)
        while(i<numNeighbors){
            seq=call neighborhood.get(myNeighbors[i]);
            if((call neighborhood.contains(myNeighbors[i])) && (innerPack->seq-seq)>acceptableMisses){
                //if last seq was at least 6s, 
                //conclude it is no longer a neighbor
                dbg(NEIGHBOR_CHANNEL,"Removing %hhu,%hhu from my list for being older than %hhu.\n",myNeighbors[i],seq,innerPack->seq-acceptableMisses);
                call neighborhood.remove(myNeighbors[i]);
                numNeighbors -= 1;
                i--;
            }
            i++;
        }
        post ping();
    }

    task void respondtoPingRequest(){
        ndpack* innerReplyPack = (ndpack*) mypingReply.payload;
        ndpack* innerPack = (ndpack*) myPack.payload;
        
        dbg(NEIGHBOR_CHANNEL,"Responding to Ping Request from %hhu\n",innerPack->src);

        innerReplyPack->seq = innerPack->seq;
        call pingSend.send(mypingReply,innerPack->src);
    }

    task void respondtoPingReply(){
        ndpack* innerPack = (ndpack*) myPack.payload;
        dbg(NEIGHBOR_CHANNEL,"Handling Ping Reply from %hhu...\n",innerPack->src);
        // logPack(pingReply,NEIGHBOR_CHANNEL);
        // dbg(NEIGHBOR_CHANNEL,"Updating %hhu,%hhu in my list\n",pingReply->src,pingReply->seq);
        call neighborhood.insert(innerPack->src,innerPack->seq);
    }

    event void PacketHandler.gotPing(uint8_t* packet){
        ndpack* innerPack = (ndpack*) myPack.payload;
        memcpy(innerPack,(ndpack*) packet,20);

        if(innerPack->protocol == PROTOCOL_PING){
            post respondtoPingRequest();
        }
        else{
            post respondtoPingReply();
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
    command void neighborDiscovery.printMyNeighbors(){
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
