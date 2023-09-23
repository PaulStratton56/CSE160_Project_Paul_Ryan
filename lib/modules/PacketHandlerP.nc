#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/protocol.h"

module PacketHandlerP{
    provides interface PacketHandler;

    uses interface neighborDiscovery as nd;
    uses interface flooding as flood;
}

implementation{

    command error_t PacketHandler.handle(pack* incomingMsg){
        switch(incomingMsg->protocol){
            case PROTOCOL_PING:
                signal PacketHandler.gotPingRequest(incomingMsg);
                break;
            case PROTOCOL_PINGREPLY:
                signal PacketHandler.gotPingReply(incomingMsg);
                break;
            case PROTOCOL_FLOOD:
                signal PacketHandler.gotflood(incomingMsg);
                break;
        }  
        return SUCCESS;
    }

}