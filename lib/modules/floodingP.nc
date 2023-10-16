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
    //Define a static flood pack for later use
    uint16_t floodSequence=0;
    floodpack myWave;
    pack myPack;

    //Function declarations
    error_t makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);

    /* == broadsend() ==
        After an incoming packet is received and stored in myWave, 
        broadcasts a packet to all neighbors EXCEPT the source of the incoming packet. */
    task void broadsend(){
        int i = 0;
        //Get and store neighbors & the number of neighbors
        uint32_t neighbor;
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        //Update the previous source with current node ID (since a packet will soon be sent out by this node)
        uint16_t prevNode = myWave.prev_src;

        myWave.prev_src = TOS_NODE_ID;
        myWave.ttl -= 1;
        //Create a pack `wave` to send out using the myWave flood pack as a payload
        call waveSend.makePack(&myPack,myWave.original_src,myWave.prev_src,PROTOCOL_FLOOD,(uint8_t*) &myWave,PACKET_MAX_PAYLOAD_SIZE);
        
        if(!call neighborhood.excessNeighbors()){ //If we know all our neighbors...
            for(i=0;i<numNeighbors;i++){
                neighbor = call neighborhood.getNeighbor(i);
                if(neighbor!=(uint32_t)prevNode && neighbor!=myWave.original_src){ //If the currently considered neighbor is not the previous or original source, propogate the wave to that node.
                    char* payload_message = (char*) myWave.payload;
                    payload_message[FLOOD_PACKET_MAX_PAYLOAD_SIZE] = '\00'; //add null terminator to end of payload to ensure end of string
                    call waveSend.send(myPack,neighbor);
                }
            }
        }
        else{ //If the table is full, there may be unknown neighbors! So broadcast as a safety measure (Less optimal, but still works).
            call waveSend.send(myPack,AM_BROADCAST_ADDR);
        }
    }

    /* == flood() ==
        Task to handle floodPacks.
        Checks if flooding of an incoming packet is necessary. 
        If so, call broadsend to propogate flooding message. */
    task void flood(){
        //If we havent seen a flood from the source before, or the sequence number from the node is newer, send the message.
        if(!call packets.contains(myWave.original_src) || call packets.get(myWave.original_src)<myWave.seq){
            if(myWave.ttl>0){ //Broadsend if valid TTL
                call packets.insert(myWave.original_src,myWave.seq); //Update sequence.
                post broadsend();
            }
            else{ //TTL expired, drop the packet.
                // dbg(FLOODING_CHANNEL,"Stopping dead packet from %d\n",myWave.original_src);
            }
        }
        else{ // Already propogated, drop the packet.
            //dbg(FLOODING_CHANNEL,"Duplicate packet from %hhu\n",myWave.prev_src);
        }
    }

    // flooding.initiate: Used by other modules to initiate a flood. Seen in routing, etc. 
    command void flooding.initiate(uint8_t ttl, uint8_t protocol, uint8_t* payload){
        floodSequence+=1;

        makeFloodPack(&myWave, TOS_NODE_ID, TOS_NODE_ID, floodSequence, ttl, protocol, payload);
        //Encapsulate pack in a SimpleSend packet and broadcast it!
        post flood();
    }

    /*==PacketHandler.gotflood(...)==
        signaled from the PacketHandler module when a node receives an incoming flood packet.
        Copies the packet into memory and then posts the flood task for implementation of flooding. */
    event void PacketHandler.gotflood(uint8_t* incomingWave){
        memcpy(&myWave,incomingWave,FLOOD_PACKET_SIZE);
        switch(myWave.protocol){
            case PROTOCOL_LINKSTATE:
                //dbg(FLOODING_CHANNEL,"LSP Flood\n");
                signal flooding.gotLSP((uint8_t*)myWave.payload);
                break;
            case PROTOCOL_FLOOD:
                // dbg(FLOODING_CHANNEL, "Regular Flood\n");
                break;
            default:
                dbg(FLOODING_CHANNEL,"I don't know what kind of flood this is.\n");
        }
        post flood();
    }

    /*== makeFloodPack(...) ==
        Creates a pack containing all useful information for the Flooding module. 
        Usually encapsulated in the payload of a SimpleSend packet, and passed by the packet handler.
        packet: a referenced `floodpack` packet to fill.
        o_src: Original source of the flood message (used to reply, etc.).
        p_src: Previous source of the flood message (used to not propogate backwards, etc.)
        seq: Sequence number of the packet (used to eliminate redundant packets, etc.)
        ttl: Time to Live of the packet (used to eliminate eternal packets, etc.)
        protocol: Determines whether the packet is a request or a reply (to respond appropriately)
        payload: Contains a message or higher level packets. */
    error_t makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload){
        packet->original_src = o_src;
        packet->prev_src = p_src;
        packet->seq = seq;
        packet->ttl = ttl;
        packet->protocol = protocol;
        memcpy(packet->payload, payload, FLOOD_PACKET_MAX_PAYLOAD_SIZE);
        return SUCCESS;
    }

    //Events used for other modules.
    event void neighborhood.neighborUpdate() {}
    event void PacketHandler.gotPing(uint8_t* _) {}   
    event void PacketHandler.gotRouted(uint8_t* _) {}
    
}