#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module PacketHandlerP{
    provides interface PacketHandler;

    uses interface NeighborDiscovery as Neighbor;
}

implementation{

    command error_t PacketHandler.handle(pack* msg){
        switch(msg->protocol){
            case PROTOCOL_NEIGHBOR:
            dbg(NEIGHBOR_CHANNEL, "Passing packet to Neighbor module\n");
            call Neighbor.handle((uint8_t*)msg->payload);
            break;
            
            default:
            dbg(GENERAL_CHANNEL, "ERROR: Protocol not recognized.",msg->protocol);
            break;
        }
    }

}