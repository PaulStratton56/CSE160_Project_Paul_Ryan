configuration S_NeighborDiscoveryC{
    provides interface S_NeighborDiscovery;
}

implementation{
    components S_NeighborDiscoveryP;
    S_NeighborDiscovery = S_NeighborDiscoveryP.S_NeighborDiscovery;

    components new TimerMilliC() as updateTimer;
    S_NeighborDiscoveryP.updateTimer -> updateTimer;

    components new SimpleSendC(AM_PACK) as sender;
    S_NeighborDiscoveryP.sender -> sender;

    components new HashmapC(uint8_t, 50) as table;
    S_NeighborDiscoveryP.table -> table;

}