configuration PacketHandlerC{
    provides interface PacketHandler;
}

implementation{
    components PacketHandlerP;
    PacketHandler = PacketHandlerP.PacketHandler;

   components new SimpleSendC(AM_PACK) as send;
   PacketHandlerP.send -> send;
}