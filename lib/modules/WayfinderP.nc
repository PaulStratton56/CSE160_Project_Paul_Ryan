#include "../../includes/LSP.h"
#include "../../includes/nqPair.h"
#include "../../includes/LSPBuffer.h"

module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
    uses interface Hashmap<nqPair> as routingTable;
    uses interface Hashmap<bool> as existenceTable;
    uses interface Hashmap<lspBuffer> as reassembler;
    uses interface Timer<TMilli> as lspTimer;
    // uses interface Timer<TMilli> as fragTimer;
    uses interface Timer<TMilli> as DijkstraTimer;
    uses interface Heap as unexplored;
    uses interface Queue<lsp> as lspQueue;
}

implementation{
    const uint8_t topo_size = 64;//buffer has 128 bytes for NQpairs
    float topoTable[64][64]; // 0 row/col unused (no "node 0")
    uint16_t maxNode=0;
    uint16_t lsp_seq = 0;
    bool sendLSPs = FALSE;

    //Function declarations
    uint16_t gotAllExpectedLSPs();
    void printRoutingTable();
    void printExistenceTable();
    void makeLSP(lsp* LSP, uint16_t src, uint16_t seq, uint8_t offset, uint8_t* pld,uint8_t length);

    /* == findPaths() ==
        Computes a routing table using Dijkstra on the stored topology table.
        Posted whenever recomputing is necessary. */
    task void findPaths(){
        uint8_t i=0;
        float potentialQuality;
        nqPair temp = {0,0};
        nqPair current = {TOS_NODE_ID, 1};
        
        // if(TOS_NODE_ID==1)dbg(LSP_CHANNEL, "==================================================RUNNING DIJKSTRA==================================================\n");
        // if(TOS_NODE_ID==1)call Wayfinder.printTopo();
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

                            temp.neighbor = (call routingTable.get(current.neighbor)).neighbor;         //copy the way we're getting to here
                            temp.quality = potentialQuality;
                            call routingTable.insert(i,temp);                               //update routing table with better path found
                        }
                    }
                }
            }
        }
        // if(TOS_NODE_ID==1)call Wayfinder.printTopo();
        // if(TOS_NODE_ID==1)call Wayfinder.printRoutingTable();

        // for(i=0;i<call existenceTable.size();i++){
        //     node = call existenceTable.getIndex(i);
        //     if((call routingTable.get(node)).neighbor==0){
        //         dbg(LSP_CHANNEL,"Removing %d from existenceTable because I think it is dead.\n",node);
        //         call existenceTable.remove(node);
        //     }
        // }
        // call Wayfinder.printTopo();
        // call Wayfinder.printRoutingTable();
        // dbg(LSP_CHANNEL,"Done with Dijkstra\n");
    }

    /* == updateTopoTable ==
        Updates the topology table using a received LSP. 
        Commonly called when receiving (or creating) a new LSP. */
    void updateTopoTable(lspBuffer* data){
        uint16_t i=0;
        uint16_t missing;

        // dbg(LSP_CHANNEL,"Updating Topo with LSP | src %d | seq: %d | connections: %d\n",data->src,data->seq,data->size/2); 
        
        if(data->src > topo_size){
            dbg(LSP_CHANNEL, "ERROR: Source ID %d> topo_size %d\n",data->src,topo_size);
            return;
        }
        //Initialize all of the LSP node's neighbors to 0.
        for(i=1;i<=maxNode;i++){
            topoTable[data->src][i]=0;
        }
        topoTable[data->src][0] = data->seq;
        if(data->src>maxNode){        //maintain maxNode of topology
            maxNode=data->src;
        }
        //Check all NQ pairs in the lsp, updating quality if necessary.
        for(i = 0; i < data->size; i+=2){
            if(data->pairs[i] == 0){ dbg(LSP_CHANNEL,"Weird 0 data in LSP\n"); break; }//should never happen cause receivedWholePacket() would have preventing calling of updateTopo
            if(data->pairs[i] > topo_size){
                dbg(LSP_CHANNEL, "LSP ERROR: Node ID %d > topo_size %d. Byte index: %d\n",data->pairs[i],topo_size,i);
                return;
            }
            if(data->pairs[i]>maxNode){        //maintain maxNode of topology
                maxNode=data->pairs[i];
            }
            // dbg(LSP_CHANNEL,"Adding connection (%d,%d,%d)\n",data->src,data->pairs[i],data->pairs[i+1]);
            // if(data->pairs[i+1]<255)dbg(LSP_CHANNEL,"Quality %d between %d and %d\n",data->pairs[i+1],data->src,data->pairs[i]);
            topoTable[data->src][data->pairs[i]] = (float)data->pairs[i+1]/255;
            if(!call existenceTable.contains(data->pairs[i])){
                call existenceTable.insert(data->pairs[i],FALSE);
            }
        }
        call existenceTable.insert(data->src,TRUE);
        // call Wayfinder.printTopo();
        
        //If we have an LSP from all nodes we know exist, run Dijkstra!
        missing = gotAllExpectedLSPs();
        if(missing==0){
            call DijkstraTimer.stop(); //also cancel timer so it doesn't rerun unnecessarily
            post findPaths();
        }
        else{
            call DijkstraTimer.startOneShot(8000);  //only wait a few seconds for a missing LSP
        }
        // dbg(LSP_CHANNEL,"Done Updating Topo with LSP | src %d | seq: %d | connections: %d\n",data->src,data->seq,data->size/2); 
    }

    /* == sendLSP ==
        Posted when NT is updated
        Create an LSP and flood it to the network. */
    task void sendLSP(){
        uint8_t i=0;
        // uint8_t j=0;
        lspBuffer myData;
        lsp myLSP;
        uint8_t* data = call neighborDiscovery.assembleData();
        if(data[0]>64){
            dbg(LSP_CHANNEL,"LSP Packet too big.  Can't send\n");
            return;
        }
        // dbg(LSP_CHANNEL,"Data to be sent: | Size: %d | %d | %d | %d | %d | %d\n",2*data[0],data[1],data[2],data[3],data[4],data[5]);
        memcpy(&(myData.pairs[0]), &(data[1]), 2*data[0]);
        
        if(data[0]<64){
            myData.pairs[2*data[0]]=0;                      //ensures byte after final quality is 0 to trigger stopping condition in updateTopoTable
        }
        // call neighborDiscovery.printMyNeighbors();
        lsp_seq += 1;
        myData.src =TOS_NODE_ID;
        myData.seq = lsp_seq;
        myData.size = 2*data[0];
        // if(TOS_NODE_ID==1){
        //     dbg(LSP_CHANNEL,"Full Data to be sent: | Src: %d |\n",myLSP.src);
        //     for(j=0;j<myData.size;j+=2){
        //         dbg(LSP_CHANNEL,"%d:(%d,%d)\n",j,myData.pairs[j],myData.pairs[j+1]);
        //     }
        // }
        for(i=0;i+lsp_max_pld_len<2*data[0];i+=lsp_max_pld_len){
            // dbg(LSP_CHANNEL,"Fragmenting... i:%d\n",i);
            makeLSP(&myLSP, TOS_NODE_ID, lsp_seq, i, &(myData.pairs[i]), lsp_max_pld_len);//first byte tells length
            call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
            // if(TOS_NODE_ID==1){
            //     dbg(LSP_CHANNEL,"Actual Data sent: | Src: %d | Offs: %d\n",myLSP.src,myLSP.offset);
            //     for(j=0;j<lsp_max_pld_len;j+=2){
            //         dbg(LSP_CHANNEL,"%d:(%d,%d)\n",j,myLSP.pld[j],myLSP.pld[j+1]);
            //     }
            // }
        }
        makeLSP(&myLSP,TOS_NODE_ID,lsp_seq,i+128,&(myData.pairs[i]),2*data[0]-i);
        call flooding.initiate(255, PROTOCOL_LINKSTATE, (uint8_t*)&myLSP);
        // if(TOS_NODE_ID==1)dbg(LSP_CHANNEL,"Last Frag Data sent: | Src: %d | Offs: %d | %d | %d | %d | %d | %d | %d\n",myLSP.src,myLSP.offset,myLSP.pld[0],myLSP.pld[1],myLSP.pld[2],myLSP.pld[3],myLSP.pld[4],myLSP.pld[5]);
        // if(TOS_NODE_ID==1){
        //     dbg(LSP_CHANNEL,"Last Frag sent: | Src: %d | Offs: %d\n",myLSP.src,myLSP.offset);
        //     for(j=0;j<2*data[0]-i;j+=2){
        //         dbg(LSP_CHANNEL,"%d:(%d,%d)\n",j,myLSP.pld[j],myLSP.pld[j+1]);
        //     }
        // }
        updateTopoTable(&myData);
        // dbg(LSP_CHANNEL, "Done Queuing my LSP frags\n");
    }

    bool receivedWholePacket(uint8_t* data,uint8_t size){
        int i=0;
        if(size==0){
            // dbg(LSP_CHANNEL,"Size is 0. haven't received whole packet.\n");
            return FALSE;
        }
        for(i=0;i<size;i++){                          //won't run until lastFrag received, since 0 until updated by lastFrag!
            if(data[i]==0){
                // dbg(LSP_CHANNEL,"data at %d is 0\n",i);
                return FALSE;
            }
        }
        // if(TOS_NODE_ID==11){
        //     for(i=0;i<size;i+=2){
        //         dbg(LSP_CHANNEL,"%d:(%d,%d)\n",i,data[i],data[i+1]);
        //     }
        // }
        return TRUE;
    }

    /* == receiveLSP ==
        Posted when Flooding signals an LSP.
        Save the incoming LSP, and update the stored topology using it. */
    task void receiveLSP(){
        if(call lspQueue.size()>0){
            lsp localLSP = call lspQueue.dequeue();
            //check timed out things
            //Checking sequence to see if valid
            // dbg(LSP_CHANNEL,"received LSP from: %d\n",localLSP.src);
            if(localLSP.seq > topoTable[localLSP.src][0]){//need more duplicate checks using offset
                lspBuffer data;
                uint32_t key = localLSP.src<<16 | localLSP.seq;
                bool lastFrag = localLSP.offset > 127;                      //get first bit as bool
                uint8_t offset = localLSP.offset & 127;                      //keep remaining bits as offset
                int i=0;
                
                // dbg(LSP_CHANNEL,"Handling Receiving of %d's LSP with offs %d\n",localLSP.src,localLSP.offset);

                if(call reassembler.contains(key)){
                    // dbg(LSP_CHANNEL,"Received another frag for src:%d | seq:%d | key:%d\n",localLSP.src,localLSP.seq,key);
                    data = call reassembler.get(key);
                }
                else{
                    // dbg(LSP_CHANNEL,"Received New LSP from %d\n",localLSP.src);
                    data.size = 0;
                }
                data.src=localLSP.src;
                data.seq=localLSP.seq;
                // data.time = call fragTimer.getNow();
                // dbg(LSP_CHANNEL,"Timer for src %d is %d\n",data.src,data.time);
                // dbg(LSP_CHANNEL,"In Receive: Data Received for %d: |Offs: %d | %d | %d | %d | %d | %d | %d\n",localLSP.src,localLSP.offset, localLSP.pld[0],localLSP.pld[1],localLSP.pld[2],localLSP.pld[3],localLSP.pld[4],localLSP.pld[5]);
                
                if(lastFrag){                       //update size now that it's known
                    //compute the total size of the fragmented packet by finding last byte of data
                    for(i=2;i<lsp_max_pld_len;i++){//final frag will have at least 2 bytes of NQ data
                        if(localLSP.pld[i]==0){
                            break;
                        }
                    }
                    data.size = offset+i;
                    // dbg(LSP_CHANNEL,"Got Last Frag. Total size of %d's LSP payload in bytes: %d, offset of packet is %d\n",data.src,data.size,offset);
                    if(data.size>127){
                        dbg(LSP_CHANNEL,"LSP Buffer Overflow from src %d offset %d, Last Frag\n", data.src,offset);
                    }
                    else{memcpy(&(data.pairs[0])+offset,&(localLSP.pld[0]),i);}
                }
                else{
                    // dbg(LSP_CHANNEL,"Not Last Frag. Offset field: %d\n",localLSP.offset);
                    if(offset+lsp_max_pld_len>127){
                        dbg(LSP_CHANNEL,"LSP Buffer Overflow from src %d offset %d, Mid Frag\n", data.src,offset);
                    }
                    else{memcpy(&(data.pairs[0])+offset,&(localLSP.pld[0]),lsp_max_pld_len);}
                }
                // dbg(LSP_CHANNEL,"Src: %d | Size: %d\n",data.src,data.size);
                if(receivedWholePacket(&(data.pairs[0]),data.size)){
                    // dbg(LSP_CHANNEL,"Got Whole Packet. Updating Topo\n");
                    updateTopoTable(&data);
                    call reassembler.remove(key);
                }
                else{
                    // dbg(LSP_CHANNEL,"Missing Pieces\n");
                    call reassembler.insert(key,data);
                }
                // dbg(LSP_CHANNEL,"Done Handling Receiving of %d's LSP\n",data.src);
            }
            else{
                // dbg(LSP_CHANNEL, "Got %d's old LSP with seq %d and offset %d\n",localLSP.src,localLSP.seq,localLSP.offset);
            }
            if(call lspQueue.size()>0){
                post receiveLSP();
            }
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
        call lspTimer.startOneShot(17000+400*TOS_NODE_ID%16);
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

        dbg(LSP_CHANNEL, "Topo:\n");
        for(i = 0 ; i < lastNode; i++){
            for(j = 0; j < (lastNode*spacing); j+=spacing){
                if(j == 0 || i == 0){ row[j] = '0'+((i+(j/spacing)))%10; }
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
            dbg(LSP_CHANNEL, "%s\n",row);
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
        dbg(LSP_CHANNEL,"Routing Table:\n");
        dbg(LSP_CHANNEL, "______________________\n");
        dbg(LSP_CHANNEL, "|Dest|NextHop|Quality|\n");
        dbg(LSP_CHANNEL, "|----|-------|-------|\n");
        for(i=1;i<=maxNode;i++){
            nextHop = call routingTable.get(i);
            dbg(LSP_CHANNEL,"|%4d|%7d|%.5f|\n", i, nextHop.neighbor, nextHop.quality);
        }
        dbg(LSP_CHANNEL, "|____|_______|_______|\n\n");
    }

    // DijkstraTimer.fired() forces a dijkstra implementation even if the full topology may not be known to allow for partial routing.
    event void DijkstraTimer.fired(){
        dbg(LSP_CHANNEL, "Missing LSP from %d, but Running Dijkstra anyway\n", gotAllExpectedLSPs());
        // printExistenceTable();
        // call Wayfinder.printTopo();
        post findPaths();
    }
    
    // lspTimer.fired: When this timer fires, allow sending LSPs and send one automatically!
    event void lspTimer.fired(){
        sendLSPs = TRUE;
        //reset enxistence table?
        post sendLSP();
        //Restart this timer to very occasionally resend LSPs.
        call lspTimer.startOneShot(61000);
    }
    // event void fragTimer.fired(){}

    /* == neighborDiscovery.neighborUpdate() ==
        Signaled from ND module when the list of neighbors changes (adding or dropping specifically)
        If allowed, send an LSP to update the network of this topology change. */
    event void neighborDiscovery.neighborUpdate(){
        if(sendLSPs){
            dbg(LSP_CHANNEL,"Neighbor update, sending LSPs\n");
            post sendLSP();
        }
    }

    /* == flooding.gotLSP(...) ==
        Signaled when the flooding module receives an LSP packet.
        Copy this LSP into memory and update the topology using this new LSP. */
    event void flooding.gotLSP(uint8_t* incomingMsg){
        lsp myLSP;
        memcpy(&myLSP, (lsp*)incomingMsg, lsp_len);
        call lspQueue.enqueue(myLSP);
        // dbg(LSP_CHANNEL,"Got LSP from %d\n", myLSP.src);
        post receiveLSP();
    }

    // printExistenceTable() prints the nodes assumed to exist by this node, and whether it has an LSP from them.
    void printExistenceTable(){
        int i=1;
        bool temp;
        dbg(LSP_CHANNEL,"Existence Table:\n");
        for(i=1;i<=maxNode;i++){
            temp = call existenceTable.get(i);
            if(temp){
                dbg(LSP_CHANNEL,"I have seen %d's LSP\n",i);
            }
            else{
                dbg(LSP_CHANNEL,"I haven't seen %d's LSP\n", i);
            }
        }
    }

    // gotAllExpectedLSPs: Checks if we have an LSP from all nodes we know exist.
    uint16_t gotAllExpectedLSPs(){
        uint16_t i=0;
        uint16_t numNodes  = call existenceTable.size();
        uint16_t node;
        // if(TOS_NODE_ID==1)dbg(LSP_CHANNEL,"I am missing:\n");
        for(i=0;i<numNodes;i++){
            node = call existenceTable.getIndex(i);
            if(!call existenceTable.get(node)){
                return node;
                // if(TOS_NODE_ID==1)dbg(LSP_CHANNEL,"Missing %d\n",node);
            }
        }
        return 0;
    }

    /* == makeLSP(...) ==
        Adds LSP headers to a payload.
        src: The id of the sending node.
        The rest are self-explanatory. */
    void makeLSP(lsp* LSP, uint16_t src, uint16_t seq, uint8_t offset, uint8_t* pld,uint8_t length){
        memset(LSP,0,lsp_len);
        LSP->src = src;
        LSP->seq = seq;
        LSP->offset = offset;
        memcpy(LSP->pld, pld, length);
    }

}