#ifndef LSP_H
#define LSP_H

#include "floodpack.h"

enum{
    lsp_header_len = 3,
    lsp_len = pkt_max_pld_len,
    lsp_max_pld_len = lsp_len - lsp_header_len
};

/* == lsp ==
	This pack contains headers for a Link State Packet.
	Usually this is given to flooding to distribute a node's link state across the network.
	src: contains the SRC of the node sending an LSP.
    seq: sequence number to determine redundant lsps.
    pld: contains Neighbor Quality pairs (NQPs) which can be used to derive a topology. */
typedef struct lsp{
    nx_uint8_t src;
    nx_uint16_t seq;
    nx_uint8_t pld[lsp_max_pld_len];
}lsp;

// logLSP(...): Prints the parameters of a given lsp to a given channel.
void logLSP(lsp* input, char channel[]){
	dbg(channel, "SRC: %d | SEQ: %d\n",
	input->src,input->seq);
}

#endif