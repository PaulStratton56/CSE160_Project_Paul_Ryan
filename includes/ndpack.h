#ifndef NDPACK_H
#define NDPACK_H

#include "packet.h"

enum{
	nd_pkt_len = 4
};

/* == ndpack ==
	This pack contains headers for the NeighborDiscovery module.
	Usually this is given to SimpleSend's payload before sending (See makeNeighborPack in NeighborDiscoveryP.nc)
	src: The source of the message (used to reply or as a key in a hash, etc.)
	seq: The sequence number of the packet (used in reliability calculations, etc.)
	protocol: Determines whether the packet is a ping or a reply (to respond appropriately)
	payload: Contains a message or higher level packets. */
typedef nx_struct ndpack{
	nx_uint8_t src;
	nx_uint16_t seq;
	nx_uint8_t ptl;
}ndpack;

// logNDPack(...): Prints the parameters of a given ndpack to a given channel.
void logNDpack(ndpack* input, char channel[]){
	dbg(channel, "Src: %d | Seq: %d | Protocol: %d",
	input->src, input->seq, input->ptl);
}

#endif
