#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"
#include <string.h>
#include <stdio.h>
module neighborDiscoveryP{
    provides interface neighborDiscovery;
    
    uses interface Timer<TMilli> as pingTimer;
    uses interface Hashmap<linkquality> as neighborhood;
    uses interface PacketHandler;
}

implementation{
    ndpack nd_pkt; //Inner pack 
    ndpack r_nd_pkt;
    float decayRate=.4; //Alpha value of the exponentially weighted moving average reliability value for neighbors.
                         //Higher values place more emphasis on recent data.
    uint8_t allowedQuality=10; //Quality threshold to consider a connection as valid.
                             //A quality below this value represents a 'too noisy' connection.
    uint8_t maxQuality = 255;
    uint16_t nd_seq = 0; //Sequence of the broadcasted pings
    uint8_t assembledData[2*32+1];//2*hashmap max size

    //Function declarations
    void makendpack(ndpack* pkt, uint8_t src, uint16_t seq, uint8_t ptl);
    
    /*== ping() ==
        Posted when the pingTimer fires.
        Increases the sequence number.
        Creates a packet to send out using NeighborDiscovery headers.
        Restarts the pingTimer.
        Broadcasts the ping. */
    task void ping(){

        //Increase the sequence number.
        nd_seq += 1;

        //Create the outbound packet.
        makendpack(&nd_pkt, TOS_NODE_ID, nd_seq, PROTOCOL_PING);

        //Send it.
        // dbg(NEIGHBOR_CHANNEL,"PING!\n");
        call PacketHandler.send(TOS_NODE_ID, (uint8_t)AM_BROADCAST_ADDR, PROTOCOL_NEIGHBOR, (uint8_t*)&nd_pkt);

        //Restart the timer.
        call pingTimer.startOneShot(7000);
    }

    /*== updateLinks() ==
        Posted when the sendTimer fires.
        Checks and updates the quality of connections to other nodes listed in a hash table.
        Uses an exponentially weighted moving average for the connection quality.
        If quality falls below 'allowedQuality' threshold, it is no longer considered as a neighbor. */
    task void updateLinks(){
        uint16_t i=0;
        linkquality status;
        uint32_t node;
        uint16_t numNeighbors = call neighborhood.size();

        //Loop through each neighbor and update link quality value.
        while(i<numNeighbors){
            node = call neighborhood.getIndex(i);
            if(call neighborhood.contains(node)){
                status=call neighborhood.get(node);

                //If the expected reply packet from a node did not show up, decrease the quality of the link.
                if(!status.recent){
                    status.quality = (uint8_t)((1-decayRate)*status.quality);
                    // dbg(NEIGHBOR_CHANNEL,"No reply from %d, Updated quality to %d\n",node,status.quality);
                }

                //If the quality of a link is below a certain threshold, remove it from the considered list of neighbors.
                if(status.quality<allowedQuality){
                    call neighborhood.remove(node);
                    dbg(NEIGHBOR_CHANNEL,"Removed %d (Quality %d < Threshold %d).\n",node,status.quality,allowedQuality);
                    signal neighborDiscovery.neighborUpdate();
                    numNeighbors -= 1;
                    i--;
                }
                else{
                    status.recent=FALSE;
                    call neighborhood.insert(node,status);
                }
            }
            else{dbg(NEIGHBOR_CHANNEL,"WEIRD PROBLEM\n");}
            i++;
        }
    }

    /*== respondtoPingRequest() ==
        Task to handle a neighbor ping from another node.
        Sends a pack back with the sequence number of the incoming pack. */
    task void respondtoPingRequest(){
        uint8_t dst = r_nd_pkt.src;
        uint16_t seq = r_nd_pkt.seq;

        //To respond, create the pack to reply with.
        makendpack(&nd_pkt, TOS_NODE_ID, seq, PROTOCOL_PINGREPLY);

        // Then, send it.
        // dbg(NEIGHBOR_CHANNEL,"Responding!\n");
        call PacketHandler.send(TOS_NODE_ID, dst, PROTOCOL_NEIGHBOR, (uint8_t*)&nd_pkt);

        // dbg(NEIGHBOR_CHANNEL,"Replied to neighbor ID %hhu\n", dst);
    }

    /*== respondtoPingReply() ==
        Task to handle a response to a ping.
        Increases the stored quality of a connection, and updates the status of incoming packets as recent (not dropped). */
    task void respondtoPingReply(){
        linkquality status;

        if(call neighborhood.contains(r_nd_pkt.src)){ //If the link is known, increase the quality of that link (because a reply was found)
            status = call neighborhood.get(r_nd_pkt.src);
            status.quality = (uint8_t)(maxQuality*decayRate) + (uint8_t)((1-decayRate)*status.quality);
            // dbg(NEIGHBOR_CHANNEL,"Reply from %d, Updated quality to %d\n",r_nd_pkt.src,status.quality);
        }
        else{ //Otherwise, create and signal the creation of a perfect new link.
            status.quality=maxQuality;
            // dbg(NEIGHBOR_CHANNEL,"Added Neighbor ID %hhu\n",r_nd_pkt.src);

            signal neighborDiscovery.neighborUpdate();
        }

        //If a reply is inbound, mark that a reply was recently seen (To prevent decrementing quality later)
        status.recent=TRUE;

        //Insert the updated link data into a table.
        call neighborhood.insert(r_nd_pkt.src,status);
    }

    /*== onBoot() ==
        The first thing that runs in this module.
        Called from Node.nc's "startDone" function.
        Posts a ping task to start the timer and introduce a node to its neighbors. */
    command void neighborDiscovery.onBoot(){
        call pingTimer.startOneShot(TOS_NODE_ID%4 * 250);
    }
    
    //getNeighbors() returns a list of node IDs that are considered neighbors.
    command uint32_t neighborDiscovery.getNeighbor(uint16_t i){
        return call neighborhood.getIndex(i);
    }

    command uint8_t neighborDiscovery.getNeighborQuality(uint16_t i){
        return (call neighborhood.get(i)).quality;
    }

    //numNeighbors() returns the number of nodes currently considered neighbors.
    command uint16_t neighborDiscovery.numNeighbors(){
        return call neighborhood.size();
    }

    //excessNeighbors() returns True if the table holding neighbor IDs is full, False otherwise.
    command bool neighborDiscovery.excessNeighbors(){
        return call neighborhood.size()==call neighborhood.maxSize();
    }

    //assembleData() returns a list of neighbors and their qualities.
    command uint8_t* neighborDiscovery.assembleData(){
        uint32_t* myNeighbors = call neighborhood.getKeys();
        uint16_t size = call neighborhood.size();
        int i=0;
        assembledData[0]=2*size+1;
        for(i=0;i<size;i++){
            assembledData[2*i+1] = myNeighbors[i];
            assembledData[2*i+2] = (call neighborhood.get(myNeighbors[i])).quality;
        }
        return &assembledData[0];
    }

    // printMyNeighbors() prints a list of neighbors to the NEIGHBOR_CHANNEL.
    command void neighborDiscovery.printMyNeighbors(){//not yuck anymore!
        uint8_t size = call neighborhood.size();
        char neighbors[(size*5)+1];
        int i;
        uint32_t* myNeighbors = call neighborhood.getKeys();
        for(i = 0; i < size*5; i+=5){
            neighbors[i] = (myNeighbors[i/5] >= 100 ? '0' + (uint8_t)(myNeighbors[i/5]/100):' ');
            neighbors[i+1] = ((myNeighbors[i/5] >= 10) ? '0' + (uint8_t)((myNeighbors[i/5]%100)/10):' ');
            neighbors[i+2] = '0' + (uint8_t)(myNeighbors[i/5]%10);
            neighbors[i+3] = ',';
            neighbors[i+4] = ' ';
        }
        neighbors[size*5] = '\00';
        dbg(NEIGHBOR_CHANNEL,"My Neighbors are: %s\n",neighbors);
    }

    /*== pingTimer.fired() ==
        signaled when pingTimer expires.
        Posts updateLinks and sends out a ping.
        The ping() event also restarts this timer to create a loop.
        (This may change to call the timer in the fired() event, depending on later issues.) */
    event void pingTimer.fired(){
        post updateLinks();
        post ping();
    }

    /*== PacketHandler.gotPing() ==
        Signaled from the PacketHandler module when receiving an incoming NeighborDiscovery packet.
        Checks the protocol of the ndpack previously stored in the SimpleSend pack, and responds appropriately.
        Also copies the pack into NeighborDiscovery memory to prevent data loss. */
    event void PacketHandler.gotPing(uint8_t* incomingMsg){
        memcpy(&r_nd_pkt, incomingMsg, nd_pkt_len);

        //Use ptl to know what to do.
        if(r_nd_pkt.ptl == PROTOCOL_PING){
            post respondtoPingRequest();
        }
        else if(r_nd_pkt.ptl == PROTOCOL_PINGREPLY){
            post respondtoPingReply();
        }
        else{
            dbg(NEIGHBOR_CHANNEL,"Packet Handler Error: Incorrectly received PROTOCOL_NEIGHBOR packet payload\n");
        }
    }

    /*== makeNeighborPack(...) ==
        Creates a pack containing all useful information for the NeighborDiscovery module. 
        Usually encapsulated in the payload of a SimpleSend packet, and passed by the packet handler.
        packet: a referenced `ndpack` packet to fill.
        src: The source of the packet (used to reply, etc.)
        seq: The sequence number of the packet (used for statistics, etc.)
        protocol: Determines whether the packet is a request or a reply (to respond appropriately)
        payload: Contains a message or higher level packets. */
    void makendpack(ndpack* pkt, uint8_t src, uint16_t seq, uint8_t ptl){
        pkt->src = src;
        pkt->seq = seq;
        pkt->ptl = ptl;
    }

    //Used for flooding, disregard.
    event void PacketHandler.gotflood(uint8_t* _){}
    event void PacketHandler.gotRouted(uint8_t* _) {}

}