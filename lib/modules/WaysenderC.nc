configuration WaysenderC{
    provides interface Waysender;
}

implementation{

    components WaysenderP;
    Waysender = WaysenderP.Waysender;

   components WayfinderC as router;
   WaysenderP.router -> router;

   components PacketHandlerC as PacketHandler;
   WaysenderP.PacketHandler -> PacketHandler;

    components new TimerMilliC() as t;
    WaysenderP.t -> t;
}