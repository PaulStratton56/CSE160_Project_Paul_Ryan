#ifndef ROUTINGPACK_H
#define ROUTINGPACK_H

# include "protocol.h"

enum{
	ROUTING_PACKET_HEADER_LENGTH = 6,
	ROUTING_PACKET_MAX_PAYLOAD_SIZE = 25 - ROUTING_PACKET_HEADER_LENGTH,
};

/*
== routingpack ==

*/
typedef nx_struct routingpack{
	nx_uint8_t original_src;
	nx_uint8_t dest;
	nx_uint16_t seq;
    nx_uint8_t ttl;
	nx_uint8_t protocol;
	nx_uint8_t payload[FLOOD_PACKET_MAX_PAYLOAD_SIZE];
}routingpack;

/*
== logFloodPack(...) ==
Prints the parameters of a given floodpack to a given channel.
*/
void logRoutingpack(routingpack* input, char channel[]){
	dbg(channel, "Og Src: %d | Dest: %d | Seq: %d | ttl: %d | Protocol: %d | Payload: %s\n",
	input->original_src,input->dest,input->seq,input->ttl,input->protocol,(char*) input->payload);
}

#endif
