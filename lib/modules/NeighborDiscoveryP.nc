#include "../../includes/packet.h"
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
        myPing.seq +=1;
        dbg(NEIGHBOR_CHANNEL,"Hello? Who's There?\n");
        call pingSend.send(myPing,AM_BROADCAST_ADDR);
        call pingTimer.startOneShot(2000);
    }
    command void neighborDiscovery.onBoot(){
        //generates warnings about using string as payload
        call pingSend.makePack(&myPing,TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_PING,0,"Who's there?", PACKET_MAX_PAYLOAD_SIZE);
        call pingSend.makePack(&mypingReply,TOS_NODE_ID,0,0,PROTOCOL_PINGREPLY,0,"I'm here!",PACKET_MAX_PAYLOAD_SIZE);
        post ping();
    }

    event void pingTimer.fired(){
        uint16_t i=0;
        uint16_t s;
        uint8_t acceptableMisses=3;
        uint16_t numNeighbors = call neighborhood.size();
        myNeighbors = call neighborhood.getKeys(); 
        //could do more analysis on data, especially if stored most recent data per node
        //could do this with hashmap of linked list, using last k interactions 
        //exponential importance model (more recent more important than a while ago)
        while(i<numNeighbors){
            s=call neighborhood.get(myNeighbors[i]);
            if((myPing.seq-s)>acceptableMisses){   
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

    task void respondtoPingRequest(){
        //can I add them as a neighbor if they ping me first?
        dbg(NEIGHBOR_CHANNEL,"Responding to Ping Request from %hhu\n",myPack.src);
        // logPack(pingRequest,NEIGHBOR_CHANNEL);
        mypingReply.dest = myPack.src;
        mypingReply.seq = myPack.seq;
        call pingSend.send(mypingReply,mypingReply.dest);
    }

    event void PacketHandler.gotPingRequest(pack* pingRequest){
        memcpy(&myPack,pingRequest,28);
        post respondtoPingRequest();
    }
    event void PacketHandler.gotflood(pack* _){}

    task void addNeighbor(){
        dbg(NEIGHBOR_CHANNEL,"Handling Ping Reply from %hhu...\n",myPack.src);
        // logPack(pingReply,NEIGHBOR_CHANNEL);
        // dbg(NEIGHBOR_CHANNEL,"Updating %hhu,%hhu in my list\n",pingReply->src,pingReply->seq);
        call neighborhood.insert(myPack.src,myPack.seq);
    }
    
    event void PacketHandler.gotPingReply(pack* pingReply){
        memcpy(&myPack,pingReply,28);
        post addNeighbor();
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
        int j=0;
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
}
