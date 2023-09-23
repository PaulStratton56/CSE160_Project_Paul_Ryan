#include "../../includes/linkquality.h"

configuration neighborDiscoveryC{
    provides interface neighborDiscovery;
}

implementation{
   components neighborDiscoveryP;
   neighborDiscovery = neighborDiscoveryP.neighborDiscovery;
   
   components new SimpleSendC(AM_PACK) as pingSend;
   neighborDiscoveryP.pingSend -> pingSend;
   
   components new TimerMilliC() as pingTimer;
   neighborDiscoveryP.pingTimer -> pingTimer;

   components new HashmapC(linkquality,32) as neighborhood;
   neighborDiscoveryP.neighborhood -> neighborhood;

   components PacketHandlerC as PacketHandler;
   neighborDiscoveryP.PacketHandler -> PacketHandler;
}