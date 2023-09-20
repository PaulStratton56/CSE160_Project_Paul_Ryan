configuration NeighborDiscoveryC{
    provides interface NeighborDiscovery;
}

implementation{
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as updateTimer;
    NeighborDiscoveryP.updateTimer -> updateTimer;

    components new SimpleSendC(AM_PACK) as sender;
    NeighborDiscoveryP.sender -> sender;

    components new HashmapC(uint8_t, 50) as table;
    NeighborDiscoveryP.table -> table;

}