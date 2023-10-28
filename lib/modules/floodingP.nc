#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/protocol.h"

 module floodingP{
    provides interface flooding;

    uses interface Hashmap<uint16_t> as packets;
    uses interface neighborDiscovery as neighborhood;
    uses interface PacketHandler;
}

implementation{
    //Define a static flood pack for later use
    uint16_t floodSequence=0;
    floodpack fl_pkt;
    pack myPack;

    //Function declarations
    void makefloodpack(floodpack* pkt, uint16_t og_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t ptl, uint8_t* pld);

    /* == broadsend() ==
        After an incoming packet is received and stored in fl_pkt, 
        broadcasts a packet to all neighbors EXCEPT the source of the incoming packet. */
    task void broadsend(){
        int i = 0;
        //Get and store neighbors & the number of neighbors
        uint32_t neighbor;
        uint16_t numNeighbors = call neighborhood.numNeighbors();
        //Update the previous source with current node ID (since a packet will soon be sent out by this node)
        uint16_t prevNode = fl_pkt.p_src;

        fl_pkt.p_src = TOS_NODE_ID;
        fl_pkt.ttl -= 1;
        
        if(!call neighborhood.excessNeighbors()){ //If we know all our neighbors...
            for(i=0;i<numNeighbors;i++){
                neighbor = call neighborhood.getNeighbor(i);
                if(neighbor!=(uint32_t)prevNode && neighbor!=fl_pkt.og_src){ //If the currently considered neighbor is not the previous or original source, propogate the wave to that node.
                    call PacketHandler.send(TOS_NODE_ID, neighbor, PROTOCOL_FLOOD, (uint8_t*) &fl_pkt);
                }
            }
        }
        else{ //If the table is full, there may be unknown neighbors! So broadcast as a safety measure (Less optimal, but still works).
            call PacketHandler.send(TOS_NODE_ID, (uint8_t)AM_BROADCAST_ADDR, PROTOCOL_FLOOD, (uint8_t*) &fl_pkt);
        }
    }

    /* == flood() ==
        Task to handle floodPacks.
        Checks if flooding of an incoming packet is necessary. 
        If so, call broadsend to propogate flooding message. */
    task void flood(){
        //If we havent seen a flood from the source before, or the sequence number from the node is newer, send the message.
        if(!call packets.contains(fl_pkt.og_src) || call packets.get(fl_pkt.og_src)<fl_pkt.seq){
            if(fl_pkt.ttl>0){ //Broadsend if valid ttl
                call packets.insert(fl_pkt.og_src,fl_pkt.seq); //Update sequence.
                post broadsend();
            }
            else{ //ttl expired, drop the packet.
                dbg(FLOODING_CHANNEL,"Stopping dead packet from %d\n",fl_pkt.og_src);
            }
        }
        else{ // Already propogated, drop the packet.
            dbg(FLOODING_CHANNEL,"Duplicate packet from %hhu\n",fl_pkt.p_src);
        }
    }

    // flooding.initiate: Used by other modules to initiate a flood. Seen in routing, etc. 
    // Assumes that pld is fragmented already to fit into a "pack".
    command void flooding.initiate(uint8_t ttl, uint8_t ptl, uint8_t* pld){
        floodSequence+=1;

        makefloodpack(&fl_pkt, TOS_NODE_ID, TOS_NODE_ID, floodSequence, ttl, ptl, pld);
        //Encapsulate pack in a SimpleSend packet and broadcast it!
        post flood();
    }

    /*==PacketHandler.gotflood(...)==
        signaled from the PacketHandler module when a node receives an incoming flood packet.
        Copies the packet into memory and then posts the flood task for implementation of flooding. */
    event void PacketHandler.gotflood(uint8_t* incomingWave){
        memcpy(&fl_pkt,incomingWave,fl_pkt_len);
        switch(fl_pkt.ptl){
            case PROTOCOL_LINKSTATE:
                //dbg(FLOODING_CHANNEL,"LSP Flood\n");
                signal flooding.gotLSP((uint8_t*)fl_pkt.pld);
                break;
            case PROTOCOL_FLOOD:
                // dbg(FLOODING_CHANNEL, "Regular Flood\n");
                break;
            default:
                dbg(FLOODING_CHANNEL,"I don't know what kind of flood this is.\n");
        }
        post flood();
    }

    /*== makefloodpack(...) ==
        Creates a pack containing all useful information for the Flooding module. 
        Usually encapsulated in the pld of a SimpleSend packet, and passed by the packet handler.
        packet: a referenced `floodpack` packet to fill.
        og_src: Original source of the flood message (used to reply, etc.).
        p_src: Previous source of the flood message (used to not propogate backwards, etc.)
        seq: Sequence number of the packet (used to eliminate redundant packets, etc.)
        ttl: Time to Live of the packet (used to eliminate eternal packets, etc.)
        ptl: Determines whether the packet is a request or a reply (to respond appropriately)
        pld: Contains a message or higher level packets. */
    void makefloodpack(floodpack* pkt, uint16_t og_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t ptl, uint8_t* pld){
        pkt->og_src = og_src;
        pkt->p_src = p_src;
        pkt->seq = seq;
        pkt->ttl = ttl;
        pkt->ptl = ptl;

        memcpy(pkt->pld, pld, fl_max_pld_len);
    }

    //Events used for other modules.
    event void neighborhood.neighborUpdate() {}
    event void PacketHandler.gotPing(uint8_t* _) {}   
    event void PacketHandler.gotRouted(uint8_t* _) {}
    
}