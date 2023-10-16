#ifndef ROUTINGPACK_H
#define ROUTINGPACK_H

# include "protocol.h"

enum{
	ROUTING_PACKET_HEADER_LENGTH = 6,
	ROUTING_PACKET_MAX_PAYLOAD_SIZE = 25 - ROUTING_PACKET_HEADER_LENGTH,
};

/* == routingpack ==
	This pack contains headers for the routing implementation.
	Uses SimpleSend as a link-layer interface to send.
	original_src: Contains the original source of the routing message (for replies, etc.)
	dest: The destination of the routing packet (for routing, etc.)
	seq: Sequence number to eliminate redundant routing packets (just in case!)
	ttl: Time to live for a routing pack (just in case!)
	protocol: Used for higher level modules
	payload: Used by higher level modules */
typedef nx_struct routingpack{
	nx_uint8_t original_src;
	nx_uint8_t dest;
	nx_uint16_t seq;
    nx_uint8_t ttl;
	nx_uint8_t protocol;
	nx_uint8_t payload[FLOOD_PACKET_MAX_PAYLOAD_SIZE];
}routingpack;

// logRoutingpack(...): Prints the parameters of a given routingpack to a given channel.
void logRoutingpack(routingpack* input, char channel[]){
	dbg(channel, "Og Src: %d | Dest: %d | Seq: %d | ttl: %d | Protocol: %d | Payload: %s\n",
	input->original_src,input->dest,input->seq,input->ttl,input->protocol,(char*) input->payload);
}

#endif
