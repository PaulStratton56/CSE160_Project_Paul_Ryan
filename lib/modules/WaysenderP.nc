#include "../../includes/packet.h"
#include "../../includes/wspack.h"

module WaysenderP{
    provides interface Waysender;

    uses interface Wayfinder as router;
    uses interface PacketHandler;
    uses interface Queue<wspack> as packets;
}

implementation{

    // Function declarations
    void makewspack(wspack* pkt, uint8_t src, uint8_t dst, uint8_t ttl, uint8_t ptl, uint8_t* pld);

    // forward: forwards the received packet according to the routing table.
    task void forward(){
        if(call packets.size()>0){
            wspack packet_to_forward = call packets.dequeue();
            if(packet_to_forward.ttl>0){
                uint8_t nextHop = call router.getRoute(packet_to_forward.dst);
                // call router.printRoutingTable();
                // call router.printTopo();
                if(nextHop == 0){ // If the next hop is unknown, stop.
                    // call router.printRoutingTable();
                    dbg(ROUTING_CHANNEL, "Not sure how to get to %d. Dropping Packet.\n", packet_to_forward.dst);
                }
                else{ // Otherwise, forward the pack.
                    call PacketHandler.send(TOS_NODE_ID, nextHop, PROTOCOL_ROUTING, (uint8_t*) &packet_to_forward);
                    dbg(ROUTING_CHANNEL,"Forwarding packet from %d to %d through %d\n",packet_to_forward.src,packet_to_forward.dst,nextHop);
                    // dbg(ROUTING_CHANNEL, "O_SRC: %d, dst: %d, N_HOP: %d, pld: '%s'\n",packet_to_forward.src, packet_to_forward.dst, nextHop, (char*)packet_to_forward.pld);
                }
            }
            else{
                dbg(ROUTING_CHANNEL, "Dead Packet. Won't Forward\n");
            }
            if(call packets.size()>0){
                post forward();
            }
        }
    }

    /* == gotRoutedPacket ==
        Posted when PacketHandler signals a routed packet.
        Checks if node is the destination to pass to higher modules, otherwise forwards the routing packet. */
    void gotRoutedPacket(wspack wsp){
        if(wsp.dst == TOS_NODE_ID){
            uint8_t* pld = (uint8_t*)wsp.pld;
            switch(wsp.ptl){
                case(PROTOCOL_TCP):
                    signal Waysender.gotTCP(pld);
                    break;

                default:
                    dbg(ROUTING_CHANNEL, "I am the routing destination!\n");
                    break;
            }
        }
        else{
            call packets.enqueue(wsp);
            post forward();
        }
    }

    // send: increments sequence, creates a pack, and forwards its own pack. Called when routing is needed.
    // Assumes that above modules have already fragmented. (TCP, etc.)
    command void Waysender.send(uint8_t ttl, uint8_t dst, uint8_t ptl, uint8_t* pld){
        wspack ws_pkt;
        makewspack(&ws_pkt, TOS_NODE_ID, dst, ttl, ptl, pld);
        call packets.enqueue(ws_pkt);
        post forward();
    }

    /* == PacketHandler.gotRouted == 
        Signaled when a routing packet is received.
        Copies the packet into memory and posts the gotRoutedPacket task. */
    event void PacketHandler.gotRouted(uint8_t* incomingMsg){
        wspack ws_pkt;
        memcpy(&ws_pkt, incomingMsg, ws_pkt_len);
        gotRoutedPacket(ws_pkt);
    }

    /*== makewspack(...) ==
        Encapsulates a payload with routing headers.
        Usually encapsulated in the payload of a SimpleSend packet, and passed by the packet handler.
        pkt: a referenced `wspack` to fill.
        src: The source of the packet (used to reply, etc.)
        dst: The destination of the packet (used for routing, etc.)
        SEQ: The sequence number of the packet (used for reliability, etc.)
        ttl: Used to prevent eternal packets (Just in case!)
        ptl: Determines where to pass the packet up to.
        pld: Contains a message or higher level packets. */
    void makewspack(wspack* pkt, uint8_t src, uint8_t dst, uint8_t ttl, uint8_t ptl, uint8_t* pld){
        pkt->src = src;
        pkt->dst = dst;
        pkt->ttl = ttl;
        pkt->ptl = ptl;

        memcpy(pkt->pld, pld, ws_max_pld_len);
    }

    /* Used for other modules, disregard. */
    event void PacketHandler.gotPing(uint8_t* _) {}
    event void PacketHandler.gotflood(uint8_t* _) {}
}