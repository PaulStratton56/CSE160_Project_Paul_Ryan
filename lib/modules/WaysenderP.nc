#include "../../includes/packet.h"
#include "../../includes/routingpack.h"

module WaysenderP{
    provides interface Waysender;

    uses interface SimpleSend as sender;
    uses interface Wayfinder as router;
    uses interface PacketHandler;
}

implementation{
    routingpack myRoute;
    pack myPack;
    uint16_t routingSeq = 0;

    // Function declarations
    void makeRoutingPack(routingpack* routePack, uint8_t original_src, uint8_t dest, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);

    // forward: forwards the received packet according to the routing table.
    task void forward(){
        if(myRoute.ttl>0){
            uint8_t nextHop = call router.getRoute(myRoute.dest);
            if(nextHop == 0){ // If the next hop is unknown, stop.
                // call router.printRoutingTable();
                dbg(ROUTING_CHANNEL, "Not sure how to get to %d. Dropping Packet.\n", myRoute.dest);
            }
            else{ // Otherwise, forward the pack using Simplesend.
                call sender.makePack(&myPack, TOS_NODE_ID, nextHop, PROTOCOL_ROUTING, (uint8_t*) &myRoute, PACKET_MAX_PAYLOAD_SIZE);
                call sender.send(myPack, nextHop);
                dbg(ROUTING_CHANNEL, "O_SRC: %d, DEST: %d, N_HOP: %d, PLD: '%s'\n",myRoute.original_src, myRoute.dest, nextHop, (char*)myRoute.payload);
            }
        }
        else{
            dbg(ROUTING_CHANNEL, "Dead Packet. Won't Forward\n");
        }
    }

    /* == gotRoutedPacket ==
        Posted when PacketHander signals a routed packet.
        Checks if node is the destination to pass to higher modules, otherwise forwards the routing packet. */
    task void gotRoutedPacket(){
        if(myRoute.dest == TOS_NODE_ID){
            switch(myRoute.protocol){
                default:
                    dbg(ROUTING_CHANNEL, "I am the routing destination!\n");
                    break;
            }
        }
        else{
            post forward();
        }
    }

    // send: increments sequence, creates a pack, and forwards its own pack. Called when routing is needed.
    command void Waysender.send(uint8_t ttl, uint8_t dest, uint8_t protocol, uint8_t* payload){
        routingSeq+=1;
        makeRoutingPack(&myRoute, TOS_NODE_ID, dest, routingSeq, ttl, protocol, payload);
        post forward();
    }

    /* == PacketHandler.gotRouted == 
        Signaled when a routing packet is received.
        Copies the packet into memory and posts the gotRoutedPacket task. */
    event void PacketHandler.gotRouted(uint8_t* incomingMsg){
        memcpy(&myRoute, incomingMsg, sizeof(routingpack));
        post gotRoutedPacket();
    }

    /*== makeRoutingPack(...) ==
        Encapsulates a payload with routing headers.
        Usually encapsulated in the payload of a SimpleSend packet, and passed by the packet handler.
        routePack: a referenced `routingpack` to fill.
        original_src: The source of the packet (used to reply, etc.)
        dest: The destination of the packet (used for routing, etc.)
        seq: The sequence number of the packet (used for reliability, etc.)
        ttl: Used to prevent eternal packets (Just in case!)
        protocol: Determines where to pass the packet up to.
        payload: Contains a message or higher level packets. */
    void makeRoutingPack(routingpack* routePack, uint8_t original_src, uint8_t dest, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload){
        routePack->original_src = original_src;
        routePack->dest = dest;
        routePack->seq = seq;
        routePack->ttl = ttl;
        routePack->protocol = protocol;

        memcpy(routePack->payload, payload, ROUTING_PACKET_MAX_PAYLOAD_SIZE);
    }

    /* Used for other modules, disregard. */
    event void PacketHandler.gotPing(uint8_t* incomingMsg) {}
    event void PacketHandler.gotflood(uint8_t* incomingMsg) {}

}