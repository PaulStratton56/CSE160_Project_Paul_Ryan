#include "../../includes/nqPair.h"


configuration WayfinderC{
    provides interface Wayfinder;
}

implementation{

    components WayfinderP;
    Wayfinder = WayfinderP.Wayfinder;

    components neighborDiscoveryC;
    WayfinderP.neighborDiscovery -> neighborDiscoveryC;

    components floodingC;
    WayfinderP.flooding -> floodingC;

    components new HashmapC(nqPair, 32) as routingTable;
    WayfinderP.routingTable -> routingTable;
    
    components new HashmapC(bool, 32) as existenceTable;
    WayfinderP.existenceTable -> existenceTable; 

    components new TimerMilliC() as lspTimer;
    WayfinderP.lspTimer -> lspTimer;
    
    components new TimerMilliC() as DijkstraTimer;
    WayfinderP.DijkstraTimer -> DijkstraTimer;

    components new HeapC(32) as unexplored;
    WayfinderP.unexplored -> unexplored;
}