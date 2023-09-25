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
    //Packs don't change often, so they are defined here for later use.
    pack myPing; //Outgoing ping pack ("Who are my neighbors?")
    pack mypingReply; //Outgoing reply pack ("I am your neighbor!")
    pack myPack; //Incoming pack storage (Like a pack register to use when processing)
    uint32_t* myNeighbors; //A list of neighboring node IDs 
    float decayRate=.25; //Alpha value of the exponentially weighted moving average reliability value for neighbors.
                         //Higher values place more emphasis on recent data.
    float allowedQuality=.4; //Quality threshhold to consider a connection as valid.
                             //A quality below this value represents a 'too noisy' connection.

    /*
    == ping() ==
    Broadcasts a neighbor request message to all neighbors.
    Posted from updateLinks, which is posted on pingTimer's firing event.
    Also increases the sequence number.
    */
    task void ping(){
        ndpack* innerPack = (ndpack*) myPing.payload;
        innerPack->seq += 1;
        dbg(NEIGHBOR_CHANNEL,"Hello? Who's There?\n");
        call pingSend.send(myPing,AM_BROADCAST_ADDR);
        call pingTimer.startOneShot(4000);
    }

    /*
    == updateLinks() ==
    Posted when the sendTimer fires.
    Checks and updates the quality of connections to other nodes listed in a hash table.
    Uses an exponentially weighted moving average for the connection quality.
    If quality falls below 'allowedQuality' threshhold, it is no longer considered as a neighbor.
    */
    task void updateLinks(){
        uint16_t i=0;
        linkquality status;
        uint16_t numNeighbors = call neighborhood.size();
        ndpack* innerPack = (ndpack*) myPing.payload;
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
    }

    /*
    == respondtoPingRequest() ==
    Task to handle a neighbor ping from another node.
    Sends a pack back with the sequence number of the incoming pack.
    */
    task void respondtoPingRequest(){
        ndpack* innerReplyPack = (ndpack*) mypingReply.payload;
        ndpack* innerPack = (ndpack*) myPack.payload;
        
        dbg(NEIGHBOR_CHANNEL,"Responding to Ping Request from %hhu\n",innerPack->src);

        innerReplyPack->seq = innerPack->seq;
        call pingSend.send(mypingReply,innerPack->src);
    }

    /*
    == respondtoPingReply() ==
    Task to handle a response to a ping.
    Increases the stored quality of a connection, and updates the status of incoming packets as recent (not dropped).
    */
    task void respondtoPingReply(){
        ndpack* innerPack = (ndpack*) myPack.payload;
        linkquality status;
        status.quality=1;
        dbg(NEIGHBOR_CHANNEL,"Handling Ping Reply from %hhu...\n",innerPack->src);
        if(call neighborhood.contains(innerPack->src)){
            status = call neighborhood.get(innerPack->src);
            status.quality = decayRate+(1-decayRate)*status.quality;
        }
        status.recent=TRUE;
        call neighborhood.insert(innerPack->src,status);
    }

    /*
    == onBoot() ==
    The first thing that runs in this module.
    Called from Node.nc's "startDone" function.
    Sets up outgoing packets for ease of use later on.
    Also posts a ping task to start the timer and introduce a node to its neighbors.
    */
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

    /*
    == pingTimer.fired() ==
    signaled when pingTimer expires.
    Posts updateLinks and sends out a ping.
    The ping() event also restarts this timer to create a loop.
    (This may change to call the timer in the fired() event, depending on later issues.)
    */
    event void pingTimer.fired(){
        post updateLinks();
        post ping();
    }
    
    /*
    == PacketHandler.gotPing() ==
    Signaled from the PacketHandler module when receiving an incoming NeighborDiscovery packet.
    Checks the protocol of the ndpack previously stored in the SimpleSend pack, and responds appropriately.
    Also copies the pack into NeighborDiscovery memory to prevent data loss.
    */
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

    //getNeighbors() returns a list of node IDs that are considered neighbors.
    command uint32_t* neighborDiscovery.getNeighbors(){
        return call neighborhood.getKeys();
    }

    //numNeighbors() returns the number of nodes currently considered neighbors.
    command uint16_t neighborDiscovery.numNeighbors(){
        return call neighborhood.size();
    }

    //excessNeighbors() returns True if the table holding neighbor IDs is full, False otherwise.
    command bool neighborDiscovery.excessNeighbors(){
        return call neighborhood.size()==call neighborhood.maxSize();
    }

    //printMyNeighbors() prints a list of neighbors to the debug console.
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

    /*
    == makeNeighborPack(...) ==
    Creates a pack containing all useful information for the NeighborDiscovery module. 
    Usually encapsulated in the payload of a SimpleSend packet, and passed by the packet handler.
    packet: a referenced `ndpack` packet to fill.
    src: The source of the packet (used to reply, etc.)
    seq: The sequence number of the packet (used for statistics, etc.)
    protocol: Determines whether the packet is a request or a reply (to respond appropriately)
    payload: Contains a message or higher level packets.
    */
    command error_t neighborDiscovery.makeNeighborPack(ndpack* packet, uint16_t src, uint8_t seq, uint8_t protocol, uint8_t* payload){
        packet->src = src;
        packet->seq = seq;
        packet->protocol = protocol;
        
        memcpy(packet->payload, payload, ND_PACKET_MAX_PAYLOAD_SIZE);
        return SUCCESS;
    }

    //Used for flooding, disregard.
    event void PacketHandler.gotflood(uint8_t* _){}

}
