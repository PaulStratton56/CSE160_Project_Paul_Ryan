#ifndef FLOODPACK_H
#define FLOODPACK_H


#include "packet.h"

enum{
	FLOOD_PACKET_HEADER_LENGTH = 6,
	FLOOD_PACKET_SIZE = PACKET_MAX_PAYLOAD_SIZE, //25
	FLOOD_PACKET_MAX_PAYLOAD_SIZE = FLOOD_PACKET_SIZE - FLOOD_PACKET_HEADER_LENGTH // 19
};

/*
== floodpack ==
This pack contains headers for the Flooding module.
Usually this is given to SimpleSend's payload before sending (See makeFloodPack in floodingP.nc)
original_src: the original source of the flooded message (used for replying, etc.)
prev_src: the most recent source of the flooded message (used to prevent redundancy, etc.)
seq: Sequence number of the packet (used to eliminate redundant packets, etc.)
ttl: Time to Live of the packet (used to eliminate eternal packets, etc.)
protocol: Determines whether the packet is a request or a reply (to respond appropriately)
payload: Contains a message or higher level packets.
*/
typedef nx_struct floodpack{
	nx_uint8_t original_src;
	nx_uint8_t prev_src;
	nx_uint16_t seq;
    nx_uint8_t ttl;
	nx_uint8_t protocol;
	nx_uint8_t payload[FLOOD_PACKET_MAX_PAYLOAD_SIZE];
}floodpack;


/*
== logFloodPack(...) ==
Prints the parameters of a given floodpack to a given channel.
*/
void logFloodpack(floodpack* input, char channel[]){
	dbg(channel, "Og Src: %d | Prev Src: %d | Seq: %d | ttl: %d | Protocol: %d | Payload: %s\n",
	input->original_src,input->prev_src,input->seq,input->ttl,input->protocol,(char*) input->payload);
}

#endif
