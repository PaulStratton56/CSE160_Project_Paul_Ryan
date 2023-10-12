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

    void makeRoutingPack(routingpack* pack, uint8_t original_src, uint8_t dest, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);

    command error_t Waysender.send(uint8_t ttl, uint8_t dest, uint8_t protocol, uint8_t* payload){
        //Called when a routing packet wants to be sent!
        //Sends a packet using a routing table.
        uint8_t nextHop = call router.getRoute(dest);
        routingSeq += 1;
        makeRoutingPack(&myRoute, TOS_NODE_ID, dest, routingSeq, ttl, protocol, payload);
        sender.makePack(&myPack, TOS_NODE_ID, nextHop, ttl, PROTOCOL_ROUTING, routingSeq, (uint8_t*) &myRoute, PACKET_MAX_PAYLOAD_SIZE);
        sender.send(myPack, nextHop);
    }

    task gotRoutedPacket(){
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
            uint8_t nextHop = call router.getRoute(dest);
            
            myRoute.ttl -= 1;
            sender.makePack(&myPack, TOS_NODE_ID, nextHop, myRoute.ttl, PROTOCOL_ROUTING, myRoute.routingSeq, (uint8_t*) &myRoute, PACKET_MAX_PAYLOAD_SIZE);
            sender.send(myPack, nextHop);
            dbg(ROUTING_CHANNEL, "Dest: %d | Forwarded to: %d\n", myRoute.dest,nextHop);
        }
        
    }

    event void PacketHandler.gotRouted(uint8_t* incomingMsg){
        //PacketHandler got a routing packet!
        //Need to do something with this incomingMsg.
        memcpy(&myRoute, incomingMsg, sizeof(incomingMsg));
        post gotRoutedPacket();
    }


    void makeRoutingPack(routingpack* pack, uint8_t original_src, uint8_t dest, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload){
        pack->original_src = original_src;
        pack->dest = dest;
        pack->seq = seq;
        pack->ttl = ttl;
        pack->protocol = protocol;

        memcpy(pack->payload, payload, ROUTING_PACKET_MAX_PAYLOAD_SIZE);
    }

    /* Used for other modules, disregard. */
    event void gotPing(uint8_t* incomingMsg) {}
    event void gotflood(uint8_t* incomingMsg) {}

}