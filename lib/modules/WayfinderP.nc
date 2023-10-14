#include "../../includes/LSP.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<uint16_t> as routingTable;
    uses interface Timer<TMilli> as lspTimer;
}

implementation{
    const uint8_t topo_size = 32;
    uint8_t topoTable[32][32]; // 0 row/col unused (no "node 0")
    lsp myLSP;
    uint16_t lspSequence = 0;
    uint8_t assembledData[2*32+1];
    bool sendLSPs = FALSE;
    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload);

    command void Wayfinder.onBoot(){
        //initialize topo to 0
        int i=0;
        int j=0;
        for(i = 0; i < topo_size; i++){
            for(j = 0; j < topo_size; j++){
                topoTable[i][j] = 0;
            }
        }
        dbg(ROUTING_CHANNEL, "Initialized Topo Table\n");
        call Wayfinder.printTopo();
        call lspTimer.startOneShot(8000);
    }

    task void findPaths(){
        //Posted when recomputing routing table is necessary.
        //Using the Topology table, run Dijkstra to update a routing table.

    }
    /* == updateTopoTable == */
    task void updateTopoTable(){
        uint8_t source = myLSP.id;
        uint8_t* payload = (uint8_t*)myLSP.payload;
        int i=0;
        for(i = 0; i < LSP_PACKET_MAX_PAYLOAD_SIZE; i+=2){
            if(payload[i] == 0){ break; }
            if(payload[i] > topo_size || source > topo_size){
                dbg(ROUTING_CHANNEL, "ERROR: ID > topo_size(%d)\n",topo_size);
            }
            topoTable[source][payload[i]] = payload[i+1];
            // dbg(ROUTING_CHANNEL, "source: %d | dest: %d | quality: %d | value: %d\n", source, payload[i], payload[i+1], topoTable[source][payload[i]]);
            call Wayfinder.printTopo();

        }
        post findPaths();
    }


    task void sendLSP(){
        //Posted when NT is updated
        //Create an LSP and flood it to the network.
        uint8_t* data = call neighborDiscovery.assembleData();
        memcpy(&assembledData, data, data[0]);
        lspSequence += 1;
        makeLSP(&myLSP, TOS_NODE_ID, lspSequence, &(assembledData[1]));//first byte tells length
        logLSP(&myLSP,FLOODING_CHANNEL);
        post updateTopoTable();
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
        dbg(ROUTING_CHANNEL, "Flooded new LSP\n");
    }

    event void lspTimer.fired(){
        dbg(ROUTING_CHANNEL,"LSP Timer Fired\n");
        sendLSPs = TRUE;
        post sendLSP();
        call lspTimer.startOneShot(256000);
    }

    task void receiveLSP(){
        //Posted when Flooding signals an LSP.
        //Update a Topology table with the new LSP.
        //check sequence
        post updateTopoTable();
    }


    command uint16_t Wayfinder.getRoute(uint16_t dest){
        //Called when the next node in a route is needed.
        //Quick lookup in the routing table. Easy peasy!
        return call routingTable.get(dest);
    }

    command void Wayfinder.printTopo(){
        //Prints the topology.
        int i, j, k, lastNode = 10, spacing = 2;
        char row[(lastNode*spacing)+1];
        // sep[(lastNode*spacing)] = '\00';

        dbg(ROUTING_CHANNEL, "Topo:\n");
        for(i = 0 ; i < lastNode; i++){
            for(j = 0; j < (lastNode*spacing); j+=spacing){
                if(j == 0 || i == 0){ row[j] = '0'+(i+(j/spacing)); }
                else if(topoTable[i][j/spacing] >= 192){ row[j] = '3'; }
                else if(topoTable[i][j/spacing] >= 128){ row[j] = '2'; }
                else if(topoTable[i][j/spacing] >= 64){ row[j] = '1'; }
                else { row[j] = '_'; }
                for(k = 1; k < spacing-1; k++){
                    row[j+k] = ' ';
                }
                row[j + spacing-1] = '|';
            } 
            row[(lastNode*spacing)] = '\00';
            dbg(ROUTING_CHANNEL, "%s\n",row);
        }
    }

    event void neighborDiscovery.neighborUpdate(){
        //When NT is updated:
        //Send a new LSP
        if(sendLSPs){
            post sendLSP();
        }
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