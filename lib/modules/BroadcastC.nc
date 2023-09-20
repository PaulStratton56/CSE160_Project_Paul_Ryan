configuration BroadcastC{
    provides interface Broadcast;
}

implementation{
    components BroadcastP;
    Broadcast = BroadcastP.Broadcast;

    components new SimpleSendC(AM_PACK);
    BroadcastP.sender -> SimpleSendC;
}