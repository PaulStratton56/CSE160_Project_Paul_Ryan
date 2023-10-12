configuration WaysenderC{
    provides interface Waysender;

    uses interface SimpleSend as sender;
    uses interface Wayfinder as router;
    uses interface PacketHandler;
}

implementation{

    components WaysenderP;
    Waysender = WaysenderP.Waysender;
   
   components new SimpleSendC(AM_PACK) as sender;
   WaysenderP.sender -> sender;

   components WayfinderC as router;
   WaysenderP.router -> router;

   components PacketHandlerC as PacketHandler;
   WaysenderP.PacketHandler -> PacketHandler;

}