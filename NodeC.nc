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

    components S_FloodC;
    Node.S_Flood -> S_FloodC;

    components S_NeighborDiscoveryC;
    Node.S_NeighborDiscovery -> S_NeighborDiscoveryC;

    components BroadcastC;
    Node.Broadcast -> BroadcastC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
}
