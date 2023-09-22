configuration FloodC{
    provides interface Flood;
}

implementation{
    components FloodP;
    Flood = FloodP.Flood;

    components new SimpleSendC(AM_PACK);
    FloodP.SimpleSend -> SimpleSendC;

    components new HashmapC(uint8_t, 50) as table; //Change the 50 to TABLE_SIZE from FloodP.
    FloodP.table -> table;

}