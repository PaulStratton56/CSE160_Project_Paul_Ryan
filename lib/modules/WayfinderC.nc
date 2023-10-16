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

    components new HashmapC(uint8_t, 32) as routingTable;
    WayfinderP.routingTable -> routingTable; 

    //stores src, seq to avoid resending old packets
   components new HashmapC(uint16_t,16) as sequences;
   WayfinderP.sequences -> sequences;


   components new TimerMilliC() as lspTimer;
   WayfinderP.lspTimer -> lspTimer;
}