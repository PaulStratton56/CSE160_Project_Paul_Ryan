configuration WayfinderC{
    provides interface Wayfinder;

    uses interface neighborDiscovery;
    uses interface flooding;
}

implementation{

    components WayfinderP;
    Wayfinder = WayfinderP.Wayfinder;

    components neighborDiscoveryC;
    WayfinderP.neighborDiscovery = neighborDiscoveryC;

    components floodingC;
    WayfinderP.flooding = floodingC;

}