#ifndef LSP_H
#define LSP_H

#include "floodpack.h"

enum{
    LSP_PACKET_HEADER_LENGTH = 3,
    LSP_PACKET_SIZE = FLOOD_PACKET_MAX_PAYLOAD_SIZE,//19
	LSP_PACKET_MAX_PAYLOAD_SIZE = LSP_PACKET_SIZE - LSP_PACKET_HEADER_LENGTH,//16
};

/* == lsp ==
	This pack contains headers for a Link State Packet.
	Usually this is given to flooding to distribute a node's link state across the network.
	id: contains the id of the node sending an LSP.
    seq: sequence number to determine redundant lsps.
    payload: contains Neighbor Quality pairs (NQPs) which can be used to derive a topology. */
typedef struct lsp{
    nx_uint8_t id;
    nx_uint16_t seq;
    nx_uint8_t payload[LSP_PACKET_MAX_PAYLOAD_SIZE];
}lsp;

// logLSP(...): Prints the parameters of a given lsp to a given channel.
void logLSP(lsp* input, char channel[]){
	dbg(channel, "id: %d | Seq: %d\n",
	input->id,input->seq);
}

#endif