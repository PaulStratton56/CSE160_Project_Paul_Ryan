#include "../../includes/LSP.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<uint16_t> as routingTable;

}

implementation{
    uint8_t TOPO_SIZE = 32;
    uint8_t topoTable[TOPO_SIZE][TOPO_SIZE]; // 0 row/col unused (no "node 0")
    lsp myLSP;
    uint16_t lspSequence = 0;


    void makeLSP(lsp* lsp, uint16_t id, uint16_t seq, uint8_t* payload);

    /* == updateTopoTable == */
    task void updateTopoTable(uint8_t source, uint8_t* payload){
        for(int i = 0; (i < LSP_PACKET_MAX_PAYLOAD_SIZE && payload[i] != 0), i+=2){
            if(payload[i] > TOPO_SIZE || source > TOPO_SIZE){
                dbg(ROUTING_CHANNEL, "ERROR: ID > TOPO_SIZE(%d)\n",TOPO_SIZE);
            }
            topoTable[source][payload[i]] = payload[i+1];
        }

    }

    command void initializeTopo(){
        for(int i = 0; i < TOPO_SIZE; i++){
            for(int j = 0; j < TOPO_SIZE; j++){
                topoTable[i][j] = 0;
            }
        }
    }

    task sendLSP(){
        //Posted when NT is updated
        //Create an LSP and flood it to the network.
        seq += 1;
        uint8_t* payload; //Gotta fill this still
        makeLSP(&myLSP, TOS_NODE_ID, lspSequence, payload);
        post updateTopoTable(TOS_NODE_ID, payload);
        flooding.initiate(250, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);

    }

    task receiveLSP(){
        //Posted when Flooding signals an LSP.
        //Update a Topology table with the new LSP.
        post updateTopoTable(myLSP.id, myLSP.payload);

    }

    task findPaths(){
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

    void makeLSP(lsp* lsp, uint16_t id, uint16_t seq, uint8_t* payload){
        lsp->id = id;
        lsp->seq = seq;
        memcpy(lsp->payload, payload, LSP_PACKET_MAX_PAYLOAD_SIZE);
    }

}