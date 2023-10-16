#include "../../includes/LSP.h"
#include "../../includes/nqPair.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<nqPair> as routingTable;
    uses interface Timer<TMilli> as lspTimer;
    uses interface Heap as unexplored;
}

implementation{
    const uint8_t topo_size = 32;
    float topoTable[32][32]; // 0 row/col unused (no "node 0")
    lsp myLSP;
    uint16_t maxNode=0;
    uint16_t lspSequence = 0;
    uint8_t assembledData[2*32+1];
    bool sendLSPs = FALSE;

    //Function declarations
    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload);
    void printRoutingTable();
    uint16_t gotAllExpectedLSPs();

    /* == findPaths() ==
        Computes a routing table using Dijkstra on the stored topology table.
        Posted whenever recomputing is necessary. */
    task void findPaths(){
        uint8_t i=0;
        float potentialQuality;
        nqPair temp = {0,0};
        nqPair current = {TOS_NODE_ID, 1};

        call routingTable.clearValues(temp);
        call unexplored.insert(current);
        call routingTable.insert(TOS_NODE_ID,current);

        // Update the routing table with neighbor qualities.
        for(i=1;i<=maxNode;i++){
            if(i!=TOS_NODE_ID && topoTable[TOS_NODE_ID][i]>0){
                temp.neighbor = i;
                temp.quality = topoTable[TOS_NODE_ID][i];
                call routingTable.insert(i,temp);
                call unexplored.insert(temp);
            }
        }

        //Running Dijkstra on the "unexplored" heap until we have a routing table!
        while(call unexplored.size() > 0){
            assignNQP(&current,call unexplored.extract());
            if(current.quality == (call routingTable.get(current.neighbor)).quality){
                for(i=1;i<=maxNode;i++){
                    if(i!=current.neighbor){
                        potentialQuality = current.quality*topoTable[current.neighbor][i];

                        if(potentialQuality > (call routingTable.get(i)).quality){
                            call unexplored.insertPair(i,potentialQuality);

                            temp.neighbor = (call routingTable.get(current.neighbor)).neighbor;
                            temp.quality = potentialQuality;
                            call routingTable.insert(i,temp);
                        }
                    }
                }
            }
        }

        temp.neighbor=0;
        temp.quality=1;

        for(i=0;i<call routingTable.size();i++){
            if((call routingTable.get(call routingTable.getIndex(i))).neighbor==0){
                call routingTable.insert(call routingTable.getIndex(i),temp);
            }
        }


    }

    /* == updateTopoTable ==
        Updates the topology table using a received LSP. 
        Commonly called when receiving (or creating) a new LSP. */
    task void updateTopoTable(){
        uint16_t i=0;
        nqPair seen = {0,1};
        nqPair notSeen = {0,0};
        uint16_t missing;

        //Initialize all of the LSP node's neighbors to 0.
        for(i=1;i<=maxNode;i++){
            topoTable[myLSP.id][i]=0;
        }

        //Check all NQ pairs in the lsp, updating quality if necessary.
        for(i = 0; i < LSP_PACKET_MAX_PAYLOAD_SIZE; i+=2){
            if(myLSP.payload[i] == 0){ break; }
            if(myLSP.payload[i] > topo_size || myLSP.id > topo_size){
                dbg(ROUTING_CHANNEL, "ERROR: ID > topo_size(%d)\n",topo_size);
            }
            else{
                topoTable[myLSP.id][myLSP.payload[i]] = (float)myLSP.payload[i+1]/255;
                call routingTable.insert(myLSP.id,seen);
                if(!call routingTable.contains(myLSP.payload[i])){
                    call routingTable.insert(myLSP.payload[i],notSeen);
                }
            }
        }

        //If we have an LSP from all nodes we know exist, run Dijkstra!
        missing = gotAllExpectedLSPs();
        if(missing==0){
            post findPaths();
        }
        else{
            //dbg(ROUTING_CHANNEL,"Missing LSP from %d\n",missing);
        }
    }

    /* == sendLSP ==
        Posted when NT is updated
        Create an LSP and flood it to the network. */
    task void sendLSP(){
        uint8_t* data = call neighborDiscovery.assembleData();

        memcpy(&assembledData, data, data[0]);
        assembledData[assembledData[0]]=0;

        lspSequence += 1;
        makeLSP(&myLSP, TOS_NODE_ID, lspSequence, &(assembledData[1]));//first byte tells length
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
        post updateTopoTable();
    }

    /* == receiveLSP ==
        Posted when Flooding signals an LSP.
        Save the incoming LSP, and update the stored topology using it. */
    task void receiveLSP(){
        //Check if this is the largest ID we've seen so far. Used when computing if we SHOULD run dijkstra.
        if(myLSP.id>maxNode){
            maxNode=myLSP.id;
        }
        //Checking sequence to see if valid
        if(myLSP.seq > topoTable[myLSP.id][0]){
            topoTable[myLSP.id][0] = myLSP.seq;
            post updateTopoTable();
        }
    }

    // onBoot: initializes a Topology Table to all "no connections"
    command void Wayfinder.onBoot(){
        uint8_t i=0, j=0;
        for(i = 0; i < topo_size; i++){
            for(j = 0; j < topo_size; j++){
                topoTable[i][j] = 0;
            }
        }
        maxNode = TOS_NODE_ID;

        //Start a timer to stall before we consider sending LSPs.
        call lspTimer.startOneShot(8000);
    }

    // getRoute(...) returns the next hop for routing.
    command uint8_t Wayfinder.getRoute(uint8_t dest){
        //Called when the next node in a route is needed.
        //Quick lookup in the routing table. Easy peasy!
        return (call routingTable.get(dest)).neighbor;
    }

    /* == printTopo() ==
        Prints the topology matrix, read as "Row ID has neighbor Column ID with quality (Row,Column)".
        Generalizes the qualities. 3 is excellent, 1 is horrible, blank is no detected connection.
        Due to the nature of the networks we're working with so far, this should be diagonally symmetric. */
    command void Wayfinder.printTopo(){
        //Prints the topology.
        uint8_t i, j, k, lastNode = maxNode+1, spacing = 2;
        char row[(lastNode*spacing)+1];

        dbg(ROUTING_CHANNEL, "Topo:\n");
        for(i = 0 ; i < lastNode; i++){
            for(j = 0; j < (lastNode*spacing); j+=spacing){
                if(j == 0 || i == 0){ row[j] = '0'+(i+(j/spacing)); }
                else if(topoTable[i][j/spacing] >= .75){ row[j] = '3'; }
                else if(topoTable[i][j/spacing] >= .5){ row[j] = '2'; }
                else if(topoTable[i][j/spacing] >= .25){ row[j] = '1'; }
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

    // lspTimer.fired: When this timer fires, allow sending LSPs and send one automatically!
    event void lspTimer.fired(){
        sendLSPs = TRUE;
        post sendLSP();
        //Restart this timer to very occasionally resend LSPs.
        call lspTimer.startOneShot(256000);
    }

    /* == neighborDiscovery.neighborUpdate() ==
        Signaled from ND module when the list of neighbors changes (adding or dropping specifically)
        If allowed, send an LSP to update the network of this topology change. */
    event void neighborDiscovery.neighborUpdate(){
        if(sendLSPs){
            post sendLSP();
        }
    }

    /* == flooding.gotLSP(...) ==
        Signaled when the flooding module receives an LSP packet.
        Copy this LSP into memory and update the topology using this new LSP. */
    event void flooding.gotLSP(uint8_t* payload){
        memcpy(&myLSP,(lsp*)payload, sizeof(lsp));
        post receiveLSP();
    }

    // gotAllExpectedLSPs: Checks if we have an LSP from all nodes we know exist.
    uint16_t gotAllExpectedLSPs(){
        uint16_t i=0;
        uint8_t numNodes = call routingTable.size();
        uint32_t key;

        for(i=0;i<numNodes;i++){
            key = call routingTable.getIndex(i);
            if((call routingTable.get(key)).quality==0){
                return key;
            }
        }
        return 0;
    }

    // printRoutingTable() prints the next hops stored in the routing table, currently.
    void printRoutingTable(){
        int i=1;
        nqPair temp;
        dbg(ROUTING_CHANNEL,"Routing Table: \n");
        for(i=1;i<=maxNode;i++){
            temp = call routingTable.get(i);
            dbg(ROUTING_CHANNEL,"To get to %d send to %d | Expected Quality: %f\n", i, temp.neighbor, temp.quality);
        }
    }

    /* == makeLSP(...) ==
        Adds LSP headers to a payload.
        id: The id of the sending node.
        The rest are self-explanatory. */
    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload){
        LSP->id = id;
        LSP->seq = seq;
        memcpy(LSP->payload, payload, LSP_PACKET_MAX_PAYLOAD_SIZE);
    }

}