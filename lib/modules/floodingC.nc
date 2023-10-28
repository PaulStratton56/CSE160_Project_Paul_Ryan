#include "../../includes/packet.h"

configuration floodingC{
    provides interface flooding;
}

implementation{
   components floodingP;
   flooding = floodingP.flooding;

    //stores src, seq to avoid resending old packets
   components new HashmapC(uint16_t,16) as packets;
   floodingP.packets -> packets;

   components neighborDiscoveryC as neighborhood;
   floodingP.neighborhood -> neighborhood;
   
   components PacketHandlerC as PacketHandler;
   floodingP.PacketHandler -> PacketHandler;
}