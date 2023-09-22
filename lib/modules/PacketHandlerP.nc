#include "../../includes/packet.h"
#include "../../includes/neighborPacket.h"
#include "../../includes/protocol.h"

module PacketHandlerP{
    provides interface PacketHandler;

    uses interface NeighborDiscovery as Neighbor;
    uses interface Flood;
}

implementation{

    command error_t PacketHandler.handle(pack* msg){
        switch(msg->protocol){
            case PROTOCOL_NEIGHBOR:
            dbg(HANDLER_CHANNEL, "Packet -> Neighbor\n");
            call Neighbor.handle( (neighborPacket*) msg->payload);
            break;
            
            case PROTOCOL_FLOOD:
            dbg(HANDLER_CHANNEL, "Packet -> Flood\n");
            call Flood.handle(msg);
            break;

            default:
            dbg(HANDLER_CHANNEL, "ERROR: Protocol not recognized.",msg->protocol);
            break;
        }
        return SUCCESS;
    }

}