/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components neighborDiscoveryC;
    Node.nd -> neighborDiscoveryC;
    
    components WayfinderC;
    Node.Wayfinder -> WayfinderC;

    components WaysenderC;
    Node.router -> WaysenderC;

    components TinyControllerC;
    Node.TCP -> TinyControllerC;

    components PacketHandlerC;
    Node.PacketHandler -> PacketHandlerC;

    components floodingC;
    Node.flood -> floodingC;

    components convoC;
    Node.convo -> convoC;

    components testConnectorC;
    Node.testConnector -> testConnectorC;
}
