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
        if(incomingMsg->protocol == PROTOCOL_PING){
            // if(TOS_NODE_ID!=3 || (incomingMsg->seq<55 || incomingMsg->seq>60))
            call nd.handlePingRequest(incomingMsg);
            return SUCCESS;
        }
        else if(incomingMsg->protocol == PROTOCOL_PINGREPLY){
           call nd.handlePingReply(incomingMsg);
           return SUCCESS;
        }
        else if(incomingMsg->protocol == PROTOCOL_FLOOD){
           call flood.flood(incomingMsg);
           return SUCCESS;
        }    
    }

}