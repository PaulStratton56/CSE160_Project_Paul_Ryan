configuration PacketHandlerC{
    provides interface PacketHandler;
}

implementation{
    components PacketHandlerP;
    PacketHandler = PacketHandlerP.PacketHandler;


}