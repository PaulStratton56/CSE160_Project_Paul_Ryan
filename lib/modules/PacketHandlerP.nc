#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/ndpack.h"
#include "../../includes/protocol.h"

module PacketHandlerP{
    provides interface PacketHandler;

    uses interface neighborDiscovery as nd;
    uses interface flooding as flood;
}

implementation{

    command error_t PacketHandler.handle(pack* incomingMsg){
        if(incomingMsg->protocol == PROTOCOL_NEIGHBOR){
            call nd.handlePack((uint8_t*) incomingMsg->payload);
        }
        else if(incomingMsg->protocol == PROTOCOL_FLOOD){
           call flood.flood((uint8_t*) incomingMsg->payload);
        }    
        return SUCCESS;
    }

}