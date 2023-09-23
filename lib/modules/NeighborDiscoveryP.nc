#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include <string.h>
#include <stdio.h>
module neighborDiscoveryP{
    provides interface neighborDiscovery;
    
    uses interface SimpleSend as pingSend;
    uses interface Timer<TMilli> as pingTimer;
    uses interface Hashmap<uint16_t> as neighborhood;
}

implementation{
    pack myPing;
    pack mypingReply;
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
        uint16_t s;
        uint8_t acceptableMisses=3;
        myNeighbors = call neighborhood.getKeys(); 
        //could do more analysis on data, especially if stored most recent data per node
        //could do this with hashmap of linked list, using last k interactions 
        //exponential importance model (more recent more important than a while ago)
        while(i<call neighborhood.size()){
            ndpack* innerPack = (ndpack*) myPing.payload;
            s=call neighborhood.get(myNeighbors[i]);
            if((innerPack->seq-s)>acceptableMisses){   
                //if last seq was at least 6s, 
                //conclude it is no longer a neighbor
                dbg(NEIGHBOR_CHANNEL,"Removing %hhu,%hhu from my list for being older than %hhu.\n",myNeighbors[i],s,myPing.seq-acceptableMisses);
                call neighborhood.remove(myNeighbors[i]);
                i--;
            }
            i++;
        }
        post ping();
    }

    command error_t neighborDiscovery.handlePack(uint8_t* alertPacket){
        ndpack* packet = (ndpack*) alertPacket;
        if(packet->protocol == PROTOCOL_PING){
            call neighborDiscovery.handlePingRequest(packet);
        }
        else{
            call neighborDiscovery.handlePingReply(packet);
        }
        return SUCCESS;
    }

    command void neighborDiscovery.handlePingRequest(ndpack* pingRequest){
        ndpack* innerPack = (ndpack*) mypingReply.payload;
        //can I add them as a neighbor if they ping me first?
        dbg(NEIGHBOR_CHANNEL,"Responding to Ping Request from %hhu\n",pingRequest->src);
        // logPack(pingRequest,NEIGHBOR_CHANNEL);
        innerPack->seq = pingRequest->seq;
        call pingSend.send(mypingReply,pingRequest->src);
    }
    
    command void neighborDiscovery.handlePingReply(ndpack* pingReply){
        dbg(NEIGHBOR_CHANNEL,"Handling Ping Reply from %hhu...\n",pingReply->src);
        // logPack(pingReply,NEIGHBOR_CHANNEL);
        // dbg(NEIGHBOR_CHANNEL,"Updating %hhu,%hhu in my list\n",pingReply->src,pingReply->seq);
        call neighborhood.insert(pingReply->src,pingReply->seq);
        dbg(NEIGHBOR_CHANNEL, "Updated %d with %d\n",pingReply->src, pingReply->seq);
        call neighborDiscovery.printMyNeighbors();
    }
    
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
        dbg(FLOODING_CHANNEL,"My Neighbors are: %s\n",buffer);
    }

    command error_t neighborDiscovery.makeNeighborPack(ndpack* packet, uint16_t src, uint8_t seq, uint8_t protocol, uint8_t* payload){
        packet->src = src;
        packet->seq = seq;
        packet->protocol = protocol;
        
        memcpy(packet->payload, payload, ND_PACKET_MAX_PAYLOAD_SIZE);
        return SUCCESS;
    }

}
