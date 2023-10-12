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

    components new HashmapC(uint16_t, 32) as routingTable;
    WayfinderP.routingTable -> routingTable; 

}