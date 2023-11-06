#include "../../includes/LSP.h"
#include "../../includes/nqPair.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<nqPair> as routingTable;
    uses interface Hashmap<bool> as existenceTable;
    uses interface Timer<TMilli> as lspTimer;
    uses interface Timer<TMilli> as DijkstraTimer;
    uses interface Heap as unexplored;
}

implementation{
    const uint8_t topo_size = 32;
    float topoTable[32][32]; // 0 row/col unused (no "node 0")
    lsp myLSP;
    uint16_t maxNode=0;
    uint16_t lsp_seq = 0;
    uint8_t assembledData[2*32+1];//first byte specifies length
    bool sendLSPs = FALSE;

    //Function declarations
    uint16_t gotAllExpectedLSPs();
    void printRoutingTable();
    void printExistenceTable();
    void makeLSP(lsp* LSP, uint16_t src, uint16_t seq, uint8_t* pld);

    /* == findPaths() ==
        Computes a routing table using Dijkstra on the stored topology table.
        Posted whenever recomputing is necessary. */
    task void findPaths(){
        uint8_t i=0;
        float potentialQuality;
        nqPair temp = {0,0};
        nqPair current = {TOS_NODE_ID, 1};
        
        // dbg(ROUTING_CHANNEL, "==================================================RUNNING DIJKSTRA==================================================\n");
        call routingTable.clearValues();                //because routing table stores old paths
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
            if(current.quality == (call routingTable.get(current.neighbor)).quality){       //if extracted value is still valid best way to reach
                for(i=1;i<=maxNode;i++){
                    if(i!=current.neighbor && topoTable[current.neighbor][i]>0){                                                //run through all neighbors
                        potentialQuality = current.quality*topoTable[current.neighbor][i];

                        if(!call routingTable.contains(i) || potentialQuality > (call routingTable.get(i)).quality){          //if found a better way
                            call unexplored.insertPair(i,potentialQuality);                 //add it to the heap to explore from later

                            temp.neighbor = (call routingTable.get(current.neighbor)).neighbor;
                            temp.quality = potentialQuality;
                            call routingTable.insert(i,temp);                               //update routing table with better path found
                        }
                    }
                }
            }
        }
        // call Wayfinder.printTopo();
        // call Wayfinder.printRoutingTable();

        // for(i=0;i<call existenceTable.size();i++){
        //     node = call existenceTable.getIndex(i);
        //     if((call routingTable.get(node)).neighbor==0){
        //         dbg(ROUTING_CHANNEL,"Removing %d from existenceTable because I think it is dead.\n",node);
        //         call existenceTable.remove(node);
        //     }
        // }
    }

    /* == updateTopoTable ==
        Updates the topology table using a received LSP. 
        Commonly called when receiving (or creating) a new LSP. */
    task void updateTopoTable(){
        uint16_t i=0;
        uint16_t missing;
        
        if(myLSP.src > topo_size){
            dbg(ROUTING_CHANNEL, "ERROR: Source ID %d> topo_size %d\n",myLSP.src,topo_size);
            return;
        }
        //Initialize all of the LSP node's neighbors to 0.
        for(i=1;i<=maxNode;i++){
            topoTable[myLSP.src][i]=0;
        }

        //Check all NQ pairs in the lsp, updating quality if necessary.
        for(i = 0; i < lsp_max_pld_len; i+=2){
            if(myLSP.pld[i] == 0){ break; }
            if(myLSP.pld[i] > topo_size){
                dbg(ROUTING_CHANNEL, "ERROR: Node ID %d > topo_size %d\n",myLSP.pld[i],topo_size);
                return;
            }
            topoTable[myLSP.src][myLSP.pld[i]] = (float)myLSP.pld[i+1]/255;
            if(!call existenceTable.contains(myLSP.pld[i])){
                call existenceTable.insert(myLSP.pld[i],FALSE);
            }
        }
        call existenceTable.insert(myLSP.src,TRUE);
        
        //If we have an LSP from all nodes we know exist, run Dijkstra!
        missing = gotAllExpectedLSPs();
        if(missing==0){
            call DijkstraTimer.stop(); //also cancel timer so it doesn't rerun unnecessarily
            post findPaths();
        }
        else{
            call DijkstraTimer.startOneShot(8000);  //only wait a few seconds for a missing LSP
        }
    }

    /* == sendLSP ==
        Posted when NT is updated
        Create an LSP and flood it to the network. */
    task void sendLSP(){
        uint8_t* data = call neighborDiscovery.assembleData();

        memcpy(&assembledData, data, data[0]);
        assembledData[assembledData[0]]=0;                              //ensures byte after final quality is 0 to trigger stopping condition in updateTopoTable

        lsp_seq += 1;

        makeLSP(&myLSP, TOS_NODE_ID, lsp_seq, &(assembledData[1]));//first byte tells length
        post updateTopoTable();
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
        // dbg(ROUTING_CHANNEL, "Flooded my LSP\n");
    }

    /* == receiveLSP ==
        Posted when Flooding signals an LSP.
        Save the incoming LSP, and update the stored topology using it. */
    task void receiveLSP(){
        //maintain maxNode of topology
        if(myLSP.src>maxNode){
            maxNode=myLSP.src;
        }

        //Checking sequence to see if valid
        if(myLSP.seq > topoTable[myLSP.src][0]){
            topoTable[myLSP.src][0] = myLSP.seq;
            post updateTopoTable();
        }
        else{
            // dbg(ROUTING_CHANNEL, "Got %d's old LSP seq:%d\n",myLSP.src,myLSP.seq);
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
        call lspTimer.startOneShot(17000+250*(TOS_NODE_ID%4));
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
                else if(topoTable[i][j/spacing] >= .98){ row[j] = 'A'; }
                else if(topoTable[i][j/spacing] >= .96){ row[j] = 'B'; }
                else if(topoTable[i][j/spacing] >= .94){ row[j] = 'C'; }
                else if(topoTable[i][j/spacing] >= .92){ row[j] = 'D'; }
                else if(topoTable[i][j/spacing] >= .9){ row[j] = '9'; }
                else if(topoTable[i][j/spacing] >= .8){ row[j] = '8'; }
                else if(topoTable[i][j/spacing] >= .7){ row[j] = '7'; }
                else if(topoTable[i][j/spacing] >= .6){ row[j] = '6'; }
                else if(topoTable[i][j/spacing] >= .5){ row[j] = '5'; }
                else if(topoTable[i][j/spacing] >= .4){ row[j] = '4'; }
                else if(topoTable[i][j/spacing] >= .3){ row[j] = '3'; }
                else if(topoTable[i][j/spacing] >= .2){ row[j] = '2'; }
                else if(topoTable[i][j/spacing] >= .1){ row[j] = '1'; }
                else if(topoTable[i][j/spacing] > 0){ row[j] = '0'; }
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

    // getMissing() returns whether the node has an LSP from all nodes it knows it exists.
    command uint16_t Wayfinder.getMissing(){
        return gotAllExpectedLSPs();
    }

    // printRoutingTable() prints the next hops stored in the routing table, currently.
    command void Wayfinder.printRoutingTable(){
        int i;
        nqPair nextHop;
        dbg(ROUTING_CHANNEL,"Routing Table:\n");
        dbg(ROUTING_CHANNEL, "______________________\n");
        dbg(ROUTING_CHANNEL, "|Dest|NextHop|Quality|\n");
        dbg(ROUTING_CHANNEL, "|----|-------|-------|\n");
        for(i=1;i<=maxNode;i++){
            nextHop = call routingTable.get(i);
            dbg(ROUTING_CHANNEL,"|%4d|%7d|%.5f|\n", i, nextHop.neighbor, nextHop.quality);
        }
        dbg(ROUTING_CHANNEL, "|____|_______|_______|\n\n");
    }

    // DijkstraTimer.fired() forces a dijkstra implementation even if the full topology may not be known to allow for partial routing.
    event void DijkstraTimer.fired(){
        dbg(ROUTING_CHANNEL, "Missing LSP from %d, but Running Dijkstra anyway\n", gotAllExpectedLSPs());
        // printExistenceTable();
        // call Wayfinder.printTopo();
        post findPaths();
    }
    
    // lspTimer.fired: When this timer fires, allow sending LSPs and send one automatically!
    event void lspTimer.fired(){
        sendLSPs = TRUE;
        post sendLSP();
        //Restart this timer to very occasionally resend LSPs.
        call lspTimer.startOneShot(61000);
    }

    /* == neighborDiscovery.neighborUpdate() ==
        Signaled from ND module when the list of neighbors changes (adding or dropping specifically)
        If allowed, send an LSP to update the network of this topology change. */
    event void neighborDiscovery.neighborUpdate(){
        if(sendLSPs){
            dbg(ROUTING_CHANNEL,"Neighbor update, sending LSPs\n");
            post sendLSP();
        }
    }

    /* == flooding.gotLSP(...) ==
        Signaled when the flooding module receives an LSP packet.
        Copy this LSP into memory and update the topology using this new LSP. */
    event void flooding.gotLSP(uint8_t* incomingMsg){
        memcpy(&myLSP, (lsp*)incomingMsg, lsp_len);
        // dbg(ROUTING_CHANNEL,"Got LSP from %d\n", myLSP.src);
        post receiveLSP();
    }

    // printExistenceTable() prints the nodes assumed to exist by this node, and whether it has an LSP from them.
    void printExistenceTable(){
        int i=1;
        bool temp;
        dbg(ROUTING_CHANNEL,"Existence Table:\n");
        for(i=1;i<=maxNode;i++){
            temp = call existenceTable.get(i);
            if(temp){
                dbg(ROUTING_CHANNEL,"I have seen %d's LSP\n",i);
            }
            else{
                dbg(ROUTING_CHANNEL,"I haven't seen %d's LSP\n", i);
            }
        }
    }

    // gotAllExpectedLSPs: Checks if we have an LSP from all nodes we know exist.
    uint16_t gotAllExpectedLSPs(){
        uint16_t i=0;
        uint16_t numNodes  = call existenceTable.size();
        uint16_t node;
        for(i=0;i<numNodes;i++){
            node = call existenceTable.getIndex(i);
            if(!call existenceTable.get(node)){
                return node;
            }
        }
        return 0;
    }

    /* == makeLSP(...) ==
        Adds LSP headers to a payload.
        src: The id of the sending node.
        The rest are self-explanatory. */
    void makeLSP(lsp* LSP, uint16_t src, uint16_t seq, uint8_t* pld){
        LSP->src = src;
        LSP->seq = seq;

        memcpy(LSP->pld, pld, lsp_max_pld_len);
    }

}