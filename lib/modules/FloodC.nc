configuration FloodC{
    provides interface Flood;
}

implementation{
    components FloodP;
    Flood = FloodP.Flood;

    components new SimpleSendC(AM_PACK);
    FloodP.SimpleSend -> SimpleSendC;

}