#ifndef FLOODPACK_H
#define FLOODPACK_H


#include "packet.h"

enum{
	fl_header_len = 6,
	fl_pkt_len = pkt_max_pld_len,
	fl_max_pld_len = fl_pkt_len - fl_header_len
};

/* == floodpack ==
	This pack contains headers for the Flooding module.
	Usually this is given to SimpleSend's payload before sending (See makeFloodPack in floodingP.nc)
	original_src: the original source of the flooded message (used for replying, etc.)
	prev_src: the most recent source of the flooded message (used to prevent redundancy, etc.)
	seq: Sequence number of the packet (used to eliminate redundant packets, etc.)
	ttl: Time to Live of the packet (used to eliminate eternal packets, etc.)
	protocol: Determines whether the packet is a request or a reply (to respond appropriately)
	payload: Contains a message or higher level packets. */
typedef nx_struct floodpack{
	nx_uint8_t og_src;
	nx_uint8_t p_src;
	nx_uint16_t seq;
    nx_uint8_t ttl;
	nx_uint8_t ptl;
	nx_uint8_t pld[fl_max_pld_len];
}floodpack;

// logFloodPack(...): Prints the parameters of a given floodpack to a given channel.
void logFloodpack(floodpack* input, char channel[]){
	dbg(channel, "Og Src: %d | Prev Src: %d | Seq: %d | ttl: %d | Protocol: %d | Payload: %s\n",
	input->og_src, input->p_src, input->seq, input->ttl, input->ptl, input->pld);
}

#endif
