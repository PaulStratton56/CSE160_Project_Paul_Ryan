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
        uint8_t* payload = (uint8_t*) incomingMsg->payload;
        switch(incomingMsg->protocol){
            case PROTOCOL_NEIGHBOR:
                signal PacketHandler.gotPing(payload);
                break;
            case PROTOCOL_FLOOD:
                signal PacketHandler.gotflood(payload);
                break;
        }  
        dbg(HANDLER_CHANNEL, "Package Payload: %s\n", incomingMsg->payload);
        return SUCCESS;
    }

}