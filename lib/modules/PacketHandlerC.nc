configuration PacketHandlerC{
    provides interface PacketHandler;
}

implementation{
    components PacketHandlerP;
    PacketHandler = PacketHandlerP.PacketHandler;

    components neighborDiscoveryC;
    PacketHandlerP.nd -> neighborDiscoveryC;

    components floodingC;
    PacketHandlerP.flood -> floodingC;

}