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

    void makeRoutingPack(routingpack* routePack, uint8_t original_src, uint8_t dest, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);

    command void Waysender.send(uint8_t ttl, uint8_t dest, uint8_t protocol, uint8_t* payload){
        //Called when a routing packet wants to be sent!
        //Sends a packet using a routing table.
        uint8_t nextHop = call router.getRoute(dest);
        if(nextHop == 0){
            dbg(ROUTING_CHANNEL, "Not sure how to get there. Stopping.\n");
        }
        else{
            routingSeq += 1;
            makeRoutingPack(&myRoute, TOS_NODE_ID, dest, routingSeq, ttl, protocol, payload);
            call sender.makePack(&myPack, TOS_NODE_ID, nextHop, PROTOCOL_ROUTING, (uint8_t*) &myRoute, PACKET_MAX_PAYLOAD_SIZE);
            call sender.send(myPack, nextHop);
            dbg(ROUTING_CHANNEL, "Sending '%s' to %d to get to %d\n",(char*)payload, nextHop, dest);
        }
    }

    task void gotRoutedPacket(){
        //Posted when PacketHandler signals a routed packet.
        //Checks if I am the destination, and if not,
        //Forwards the packet according to the routing table.

        if(myRoute.dest == TOS_NODE_ID){
            switch(myRoute.protocol){
                default:
                    dbg(ROUTING_CHANNEL, "I am the routing destination!\n");
                    break;
            }
        }
        else{
            uint8_t nextHop = call router.getRoute(myRoute.dest);
            
            myRoute.ttl -= 1;
            call sender.makePack(&myPack, TOS_NODE_ID, nextHop, PROTOCOL_ROUTING, (uint8_t*) &myRoute, PACKET_MAX_PAYLOAD_SIZE);
            call sender.send(myPack, nextHop);
            dbg(ROUTING_CHANNEL, "Dest: %d | Forwarded to: %d\n", myRoute.dest,nextHop);
        }
        
    }

    event void PacketHandler.gotRouted(uint8_t* incomingMsg){
        //PacketHandler got a routing packet!
        //Need to do something with this incomingMsg.
        memcpy(&myRoute, incomingMsg, sizeof(routingpack));
        post gotRoutedPacket();
    }


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