configuration S_FloodC{
    provides interface S_Flood;
}

implementation{
    components S_FloodP;
    S_Flood = S_FloodP.S_Flood;

    components new SimpleSendC(AM_PACK);
    S_FloodP.SimpleSend -> SimpleSendC;

}