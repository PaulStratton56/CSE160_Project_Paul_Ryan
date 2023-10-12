#include "../../includes/LSP.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<uint16_t> as routingTable;

}

implementation{
    const uint8_t topo_size = 32;
    uint8_t topoTable[32][32]; // 0 row/col unused (no "node 0")
    lsp myLSP;
    uint16_t lspSequence = 0;


    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload);

    /* == updateTopoTable == */
    task void updateTopoTable(){
        uint8_t source = myLSP.id;
        uint8_t* payload = (uint8_t*)myLSP.payload;
        int i=0;
        for(i = 0; i < LSP_PACKET_MAX_PAYLOAD_SIZE && payload[i] != 0; i+=2){
            if(payload[i] > topo_size || source > topo_size){
                dbg(ROUTING_CHANNEL, "ERROR: ID > topo_size(%d)\n",topo_size);
            }
            topoTable[source][payload[i]] = payload[i+1];
        }

    }

    command void Wayfinder.initializeTopo(){
        int i=0;
        int j=0;
        for(i = 0; i < topo_size; i++){
            for(j = 0; j < topo_size; j++){
                topoTable[i][j] = 0;
            }
        }
    }

    task void sendLSP(){
        //Posted when NT is updated
        //Create an LSP and flood it to the network.
        uint8_t* payload = (uint8_t*)myLSP.payload; //Gotta fill this still
        lspSequence += 1;
        makeLSP(&myLSP, TOS_NODE_ID, lspSequence, payload);
        post updateTopoTable();
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);

    }

    task void receiveLSP(){
        //Posted when Flooding signals an LSP.
        //Update a Topology table with the new LSP.
        post updateTopoTable();

    }

    task void findPaths(){
        //Posted when recomputing routing table is necessary.
        //Using the Topology table, run Dijkstra to update a routing table.

    }

    command uint16_t Wayfinder.getRoute(uint16_t dest){
        //Called when the next node in a route is needed.
        //Quick lookup in the routing table. Easy peasy!
        return call routingTable.get(dest);
    }

    event void neighborDiscovery.neighborUpdate(){
        //When NT is updated:
        //Send a new LSP
        post sendLSP();

    }

    event void flooding.gotLSP(uint8_t* payload){
        //When an LSP is received:
        //Update the Topo Table!
        lsp* incomingLSP = (lsp*) payload;
        memcpy(&myLSP,incomingLSP, sizeof(lsp));
        post receiveLSP();
    }

    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload){
        LSP->id = id;
        LSP->seq = seq;
        memcpy(LSP->payload, payload, LSP_PACKET_MAX_PAYLOAD_SIZE);
    }

}