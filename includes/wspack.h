#ifndef ROUTINGPACK_H
#define ROUTINGPACK_H

# include "packet.h"

enum{
	ws_header_len = 4,
	ws_pkt_len = pkt_max_pld_len,
	ws_max_pld_len = ws_pkt_len - ws_header_len
};

/* == wspack ==
	This pack contains headers for the routing implementation.
	Uses SimpleSend as a link-layer interface to send.
	src: Contains the original source of the routing message (for replies, etc.)
	dst: The destination of the routing packet (for routing, etc.)
	SEQ: Sequence number to eliminate redundant routing packets (just in case!)
	ttl: Time to live for a routing pack (just in case!)
	ptl: Used for higher level modules
	pld: Used by higher level modules */
typedef nx_struct wspack{
	nx_uint8_t src;
	nx_uint8_t dst;
    nx_uint8_t ttl;
	nx_uint8_t ptl;
	nx_uint8_t pld[ws_max_pld_len];
}wspack;

// logwspack(...): Prints the parameters of a given wspack to a given channel.
void logwspack(wspack* input, char channel[]){
	dbg(channel, "src: %d | dst: %d | ttl: %d | ptl: %d | pld: %s\n",
	input->src, input->dst, input->ttl, input->ptl, input->pld);
}

#endif
