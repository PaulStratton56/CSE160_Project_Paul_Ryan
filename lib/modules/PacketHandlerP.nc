#include "../../includes/packet.h"
#include "../../includes/floodpack.h"
#include "../../includes/ndpack.h"
#include "../../includes/protocol.h"

/*
== PacketHandler ==
Provides a module for Node to quickly pass an incoming packet to.
Takes an incoming 'pack' and checks protocol to signal to higher level modules.
*/
module PacketHandlerP{
    provides interface PacketHandler;

}

implementation{

    command error_t PacketHandler.handle(pack* incomingMsg){
        //Strip SimpleSend header by getting 'payload'
        uint8_t* payload = (uint8_t*) incomingMsg->payload;
        //Check the SimpleSend protocol to pass to higher level modules.
        switch(incomingMsg->protocol){
            case PROTOCOL_NEIGHBOR:
                signal PacketHandler.gotPing(payload);
                break;
            case PROTOCOL_FLOOD:
                signal PacketHandler.gotflood(payload);
                break;
            case PROTOCOL_ROUTING:
                signal PacketHandler.gotRouted(payload);
                break;
        }  
        dbg(HANDLER_CHANNEL, "Package Payload: %s\n", incomingMsg->payload);
        return SUCCESS;
    }

}