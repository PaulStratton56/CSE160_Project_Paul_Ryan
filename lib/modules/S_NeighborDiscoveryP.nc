#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module S_NeighborDiscoveryP{
    provides interface S_NeighborDiscovery;

    uses interface Timer<TMilli> as updateTimer;
    uses interface SimpleSend as sender;
    uses interface Hashmap<uint8_t> as table;
}

implementation{
    uint16_t QUERY_SEQUENCE = 0;
    uint16_t REPLY_SEQUENCE = 0;
    uint8_t PING_INTERVAL = -1;
    uint8_t TABLE_SIZE = 50; //If you change this, also update in component file 'table' component.
    uint8_t targetNode;

    void makeNeighborPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

    task void ping(){
        pack queryPack;
        uint8_t payload[2] = {TOS_NODE_ID, PROTOCOL_NEIGHBORQUERY};

        makeNeighborPack(&queryPack, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_NEIGHBOR, QUERY_SEQUENCE++, payload, PACKET_MAX_PAYLOAD_SIZE);
        
        if(PING_INTERVAL == -1){
            dbg(NEIGHBOR_CHANNEL, "ERROR: Must setInterval before pinging.\n");
        }

        call sender.send(queryPack, AM_BROADCAST_ADDR);
        dbg(NEIGHBOR_CHANNEL, "Broadcasted neighbor query\n");
    }

    task void reply(){
        pack replyPack;
        uint8_t payload[2] = {TOS_NODE_ID, PROTOCOL_NEIGHBORREPLY};

        makeNeighborPack(&replyPack, TOS_NODE_ID, targetNode, 0, PROTOCOL_NEIGHBOR, REPLY_SEQUENCE++, payload, PACKET_MAX_PAYLOAD_SIZE);

        call sender.send(replyPack, targetNode);
        dbg(NEIGHBOR_CHANNEL, "Responded to %d\n", targetNode);

    }

    task void addNeighbor(){
        call table.insert(targetNode, 3);
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

    command error_t S_NeighborDiscovery.handle(uint8_t* payload){
        uint8_t protocol = payload[1];
        
        if(protocol == PROTOCOL_NEIGHBORQUERY){
            targetNode = payload[0];
            dbg(NEIGHBOR_CHANNEL, "Neighbor ID: %d, Message Type: QUERY\n",targetNode);

            post reply();
        }
        else if(protocol == PROTOCOL_NEIGHBORREPLY){
            targetNode = payload[0];
            dbg(NEIGHBOR_CHANNEL, "Neighbor ID: %d, Message Type: REPLY\n",targetNode);

            post addNeighbor(); 
        }
        else{
            dbg(NEIGHBOR_CHANNEL, "ERROR: Neighbor payload has no recognizable protocol.\n");
            return FAIL;
        }
        return SUCCESS;

    }

    command error_t S_NeighborDiscovery.setInterval(uint8_t interval){
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

    void makeNeighborPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->dest = dest;
        Package->src = src;
        Package->seq = seq;
        Package->TTL = 0;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

}