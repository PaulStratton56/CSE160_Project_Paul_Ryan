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
    // nqPair info;
    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload);
    void printRoutingTable();

    command void Wayfinder.onBoot(){
        //initialize topo to 0
        int i=0;
        int j=0;
        for(i = 0; i < topo_size; i++){
            for(j = 0; j < topo_size; j++){
                topoTable[i][j] = 0;
            }
        }
        maxNode = TOS_NODE_ID;
        dbg(ROUTING_CHANNEL, "Initialized Topo Table\n");
        // call Wayfinder.printTopo();
        call lspTimer.startOneShot(8000);
        // info.neighbor = TOS_NODE_ID;
        // info.quality = .456;
    }

    task void findPaths(){
        if(TOS_NODE_ID == 3){
            //Posted when recomputing routing table is necessary.
            //Using the Topology table, run Dijkstra to update a routing table.
            /*if(TOS_NODE_ID==3){//testing heap
                dbg(ROUTING_CHANNEL,"Finding Shortest Paths\n");
                call unexplored.insert(info);
                info.quality*=17;
                info.quality = info.quality - (int) info.quality;
                call unexplored.print();
                if(info.quality>.8){
                    call unexplored.extract();
                    call unexplored.extract();
                    call unexplored.print();
                }
            }*/
            int i=0;
            float potentialQuality;
            nqPair temp = {0,0};
            nqPair current = {TOS_NODE_ID, 1};
            dbg(ROUTING_CHANNEL, "Running Dijkstra\n");
            call Wayfinder.printTopo();
            call routingTable.clearValues(temp);
            call unexplored.insert(current);
            call routingTable.insert(TOS_NODE_ID,current);

            for(i=1;i<maxNode;i++){
                if(i!=TOS_NODE_ID && topoTable[TOS_NODE_ID][i]>0){
                    temp.neighbor = i;
                    temp.quality = topoTable[TOS_NODE_ID][i];
                    call routingTable.insert(i,temp);
                    call unexplored.insert(temp);
                }
            }

            while(call unexplored.size() > 0){
                assignNQP(&current,call unexplored.extract());            
                if(current.quality == (call routingTable.get(current.neighbor)).quality){
                    // dbg(ROUTING_CHANNEL, "Currently Considering: Node %d with Quality %f\n",current.neighbor,current.quality);
                    for(i=1;i<=maxNode;i++){
                        if(i!=current.neighbor){
                            potentialQuality = current.quality*topoTable[current.neighbor][i];
                            if(potentialQuality > (call routingTable.get(i)).quality){
                                // dbg(ROUTING_CHANNEL, "Going to %d from %d with Quality %f is better than with %f\n",i,current.neighbor,potentialQuality,(call routingTable.get(i)).quality);
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
            printRoutingTable();
        }
    }

    uint16_t gotAllExpectedLSPs(){
        uint16_t i=0;
        int numNodes = call routingTable.size();
        uint32_t key;
        for(i=0;i<numNodes;i++){
            key = call routingTable.getIndex(i);
            if((call routingTable.get(key)).quality==0){
                return key;
            }
        }
        return 0;
    }

    /* == updateTopoTable == */
    task void updateTopoTable(){
        int i=0;
        nqPair seen = {0,1};
        nqPair notSeen = {0,0};
        uint16_t missing;
        for(i=1;i<=maxNode;i++){
            topoTable[source][i]=0;
        }
        for(i = 0; i < LSP_PACKET_MAX_PAYLOAD_SIZE; i+=2){
            if(myLSP.payload[i] == 0){ break; }
            if(myLSP.payload[i] > topo_size || myLSP.id > topo_size){
                dbg(ROUTING_CHANNEL, "ERROR: ID > topo_size(%d)\n",topo_size);
            }
            else{
                topoTable[source][payload[i]] = (float)payload[i+1]/255;
                call routingTable.insert(source,seen);
                if(!call routingTable.contains(payload[i])){
                    call routingTable.insert(payload[i],notSeen);
                }
            }
            // {dbg(ROUTING_CHANNEL, "source: %d | seq: %d | dest: %d | quality: %d\n", source, myLSP.seq, payload[i], payload[i+1]);
            // call Wayfinder.printTopo();
        }
        missing = gotAllExpectedLSPs();
        if(missing==0){
            post findPaths();
        }
        else{
            if(TOS_NODE_ID==3){dbg(ROUTING_CHANNEL,"Missing LSP from %d\n",missing);}
        }
    }


    task void sendLSP(){
        //Posted when NT is updated
        //Create an LSP and flood it to the network.
        uint8_t* data = call neighborDiscovery.assembleData();
        memcpy(&assembledData, data, data[0]);
        assembledData[assembledData[0]]=0;
        lspSequence += 1;
        makeLSP(&myLSP, TOS_NODE_ID, lspSequence, &(assembledData[1]));//first byte tells length
        if(TOS_NODE_ID==3){dbg(ROUTING_CHANNEL,"Updating TopoTable because my neighbors changed\n");}
        // logLSP(&myLSP,ROUTING_CHANNEL);
        post updateTopoTable();
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
        dbg(ROUTING_CHANNEL, "Initiated LSP Flood\n");
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
        if(myLSP.id>maxNode){
            maxNode=myLSP.id;
        }
        if(myLSP.seq > topoTable[myLSP.id][0]){
            if(TOS_NODE_ID==3){dbg(ROUTING_CHANNEL,"Updating TopoTable because %d's neighbors changed\n", myLSP.id);}
            topoTable[myLSP.id][0] = myLSP.seq;
            post updateTopoTable();
        }
    }


    command uint8_t Wayfinder.getRoute(uint8_t dest){
        //Called when the next node in a route is needed.
        //Quick lookup in the routing table. Easy peasy!
        return (call routingTable.get(dest)).neighbor;
    }

    command void Wayfinder.printTopo(){
        //Prints the topology.
        uint8_t i, j, k, lastNode = maxNode+1, spacing = 2;
        char row[(lastNode*spacing)+1];
        // sep[(lastNode*spacing)] = '\00';

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

    void printRoutingTable(){
        int i=1;
        nqPair temp;
        dbg(ROUTING_CHANNEL,"Routing Table: \n");
        for(i=1;i<=maxNode;i++){
            temp = call routingTable.get(i);
            dbg(ROUTING_CHANNEL,"To get to %d send to %d | Expected Quality: %f\n", i, temp.neighbor, temp.quality);
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
        memcpy(&myLSP,(lsp*)payload, sizeof(lsp));
        post receiveLSP();
    }

    void makeLSP(lsp* LSP, uint16_t id, uint16_t seq, uint8_t* payload){
        LSP->id = id;
        LSP->seq = seq;
        memcpy(LSP->payload, payload, LSP_PACKET_MAX_PAYLOAD_SIZE);
    }

}