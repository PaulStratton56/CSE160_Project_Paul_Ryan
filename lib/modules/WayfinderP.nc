module WayfinderP{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
}

implementation{

    task sendLSP(){
        //Posted when NT is updated
        //Create an LSP and flood it to the network.

    }

    task receiveLSP(){
        //Posted when Flooding signals an LSP.
        //Update a Topology table with the new LSP.

    }

    task findPaths(){
        //Posted when recomputing routing table is necessary.
        //Using the Topology table, run Dijkstra to update a routing table.

    }

    command uint16_t Wayfinder.getRoute(uint16_t dest){
        //Called when the next node in a route is needed.
        //Quick lookup in the routing table. Easy peasy!

    }

    event void neighborDiscovery.neighborUpdate(){
        //When NT is updated:
        //Send a new LSP
        post sendLSP();

    }

}