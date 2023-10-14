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

    //Function prototype
    error_t makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);
    task void broadsend();
    task void flood();

    //interface for another module initiating a flood
    command void flooding.initiate(uint8_t ttl, uint8_t protocol, uint8_t* payload){
        floodSequence+=1;

        makeFloodPack(&myWave, TOS_NODE_ID, TOS_NODE_ID, floodSequence, ttl, protocol, payload);
        //Encapsulate pack in a SimpleSend packet and broadcast it!
        post flood();
    }

    /*== broadsend() ==
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
                if(neighbor!=(uint32_t)prevNode){ //If the currently considered neighbor is not the previous source, propogate the wave to that node.
                    
                    char* payload_message = (char*) myWave.payload;
                    payload_message[FLOOD_PACKET_MAX_PAYLOAD_SIZE] = '\00';//add null terminator to end of payload to ensure end of string
                    dbg(FLOODING_CHANNEL,"Propagating Flood sent to me by %d. Sending to %d\n", prevNode, neighbor);
                    
                    call waveSend.send(myPack,neighbor);
                }
            }
        }
        else{ //If the table is full, there may be unknown neighbors! So broadcast as a safety measure (Less optimal, but still works).
            dbg(FLOODING_CHANNEL,"Max Neighbors, so broadcasting flood wave...\n");
            call waveSend.send(myPack,AM_BROADCAST_ADDR);
        }
    }

    /*== flood() ==
        Task to handle floodPacks.
        Checks if flooding of an incoming packet is necessary. 
        If so, call broadsend to propogate flooding message. */
    task void flood(){
        //Firstly, let's see if the floodPack has anything useful.

        //If the original source hasn't flooded a packet using this node yet,
        //OR the last packet seen by this node from the original source has an older sequence number, the message SHOULD send.
        if(!call packets.contains(myWave.original_src) || call packets.get(myWave.original_src)<myWave.seq){
            //If the packet's TTL is still valid, broadsend the packet.
            if(myWave.ttl>0){
                //Update the hash table with the most recent sequence number.
                call packets.insert(myWave.original_src,myWave.seq);
                
                call neighborhood.printMyNeighbors();
                post broadsend();
            }
            //Otherwise, the packet is dead, don't propogate.
            else{
                dbg(FLOODING_CHANNEL,"Dead Packet. Won't Propagate\n");
            }
        }
        //If both of the outer conditions are false, the packet has already been propogated, so drop it.
        else{
            char* payload_message = (char*) myWave.payload;
            payload_message[FLOOD_PACKET_MAX_PAYLOAD_SIZE] = '\00';//add null terminator to end of payload to ensure end of string
            dbg(FLOODING_CHANNEL,"Already propagated '%s'. Duplicate came from %hhu\n",payload_message,myWave.prev_src);
        }
    }

    /*==PacketHandler.gotflood(...)==
        signaled from the PacketHandler module when a node receives an incoming flood packet.
        Copies the packet into memory and then posts the flood task for implementation of flooding. */
    event void PacketHandler.gotflood(uint8_t* incomingWave){
        memcpy(&myWave,incomingWave,FLOOD_PACKET_SIZE);
        logFloodpack((floodpack*)incomingWave, FLOODING_CHANNEL);
        switch(myWave.protocol){
            case PROTOCOL_LINKSTATE:
                // dbg(FLOODING_CHANNEL,"LSP Flood\n");
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