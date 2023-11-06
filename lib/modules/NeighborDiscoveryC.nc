#include "../../includes/linkquality.h"

configuration neighborDiscoveryC{
    provides interface neighborDiscovery;
}

implementation{
   components neighborDiscoveryP;
   neighborDiscovery = neighborDiscoveryP.neighborDiscovery;
   
   components new TimerMilliC() as pingTimer;
   neighborDiscoveryP.pingTimer -> pingTimer;

   //store quality data on set of neighbors
   components new HashmapC(linkquality,256) as neighborhood;
   neighborDiscoveryP.neighborhood -> neighborhood;

   components PacketHandlerC as PacketHandler;
   neighborDiscoveryP.PacketHandler -> PacketHandler;
}