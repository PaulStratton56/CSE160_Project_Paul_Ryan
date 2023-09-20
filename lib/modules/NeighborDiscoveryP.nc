#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/neighborPacket.h"

module NeighborDiscoveryP{
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as updateTimer;
    uses interface SimpleSend as sender;
    uses interface Hashmap<uint8_t> as table;
}

implementation{
    uint16_t QUERY_SEQUENCE = 0;
    uint16_t REPLY_SEQUENCE = 0;
    uint8_t PING_INTERVAL = -1;
    uint8_t MAX_AGE = 5;
    uint8_t TABLE_SIZE = 50; //If you change this, also update in component file 'table' component.
    uint8_t targetNode;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

    task void ping(){
        pack queryPack;
        uint8_t payload[0];
        
        makePack(&queryPack, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_NEIGHBORQUERY, QUERY_SEQUENCE++, payload, PACKET_MAX_PAYLOAD_SIZE);
        
        if(PING_INTERVAL == -1){
            dbg(NEIGHBOR_CHANNEL, "ERROR: Must setInterval before pinging.\n");
        }

        call sender.send(queryPack, AM_BROADCAST_ADDR);
        dbg(NEIGHBOR_CHANNEL, "Broadcasted neighbor query\n");
    }

    task void reply(){
        pack replyPack;
        uint8_t payload[0];

        makePack(&replyPack, TOS_NODE_ID, targetNode, 0, PROTOCOL_NEIGHBORREPLY, REPLY_SEQUENCE++, payload, PACKET_MAX_PAYLOAD_SIZE);

        call sender.send(replyPack, targetNode);
        dbg(NEIGHBOR_CHANNEL, "Responded to %d\n", targetNode);

    }

    task void addNeighbor(){
        call table.insert(targetNode, MAX_AGE);
        dbg(NEIGHBOR_CHANNEL,"Added node %d as neighbor\n", targetNode);
        dbg(NEIGHBOR_CHANNEL,"Node %d now has age value of %d\n",targetNode, call table.get(targetNode));
    }

    task void removeNeighbor(){
        uint8_t i;
        for(i = 0; i < TABLE_SIZE; i++){
            uint8_t age = call table.get(i);
            if(age > 0){
                call table.insert(i, age-1);
                dbg(NEIGHBOR_CHANNEL, "node %d age updated to %d\n",i,age-1);
                if(age == 1){
                    dbg(NEIGHBOR_CHANNEL, "Removed node %d as neighbor\n",i);
                }
            }
        }
    }

    command error_t NeighborDiscovery.handle(neighborPacket* payload){
        if(payload->protocol == PROTOCOL_NEIGHBORQUERY){
            targetNode = payload->src;
            dbg(NEIGHBOR_CHANNEL, "Neighbor ID: %d, Message Type: QUERY\n",payload->src);

            post reply();
        }
        else if(payload->protocol == PROTOCOL_NEIGHBORREPLY){
            targetNode = payload->src;
            dbg(NEIGHBOR_CHANNEL, "Neighbor ID: %d, Message Type: REPLY\n",payload->src);

            post addNeighbor(); 
        }
        else{
            dbg(NEIGHBOR_CHANNEL, "ERROR: Neighbor payload has no recognizable protocol.\n");
            return FAIL;
        }
        return SUCCESS;

    }

    command error_t NeighborDiscovery.setInterval(uint8_t interval){
        PING_INTERVAL = interval;
        dbg(NEIGHBOR_CHANNEL, "Set ping interval to %d\n",interval);
        call updateTimer.startOneShot(PING_INTERVAL*1000);

        return SUCCESS;
    }

    event void updateTimer.fired(){
        post ping();
        post removeNeighbor();
        call updateTimer.startOneShot(PING_INTERVAL*1000);
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        neighborPacket* neighborMsg = (neighborPacket*) Package->payload;
        
        Package->dest = dest;
        Package->src = src;
        Package->seq = seq;
        Package->TTL = 0;
        Package->protocol = PROTOCOL_NEIGHBOR;
        
        neighborMsg->src = src;
        neighborMsg->protocol = protocol;
        memcpy(neighborMsg->payload,payload,length - sizeof(neighborPacket));

    }

}