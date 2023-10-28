//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


# include "protocol.h"
#include "channels.h"

enum{
	pkt_header_len = 3,
	pkt_len = 28,
	pkt_max_pld_len = 28 - pkt_header_len //25
};


typedef nx_struct pack{
	nx_uint8_t src;
	nx_uint8_t dst;
	nx_uint8_t ptl;
	nx_uint8_t pld[pkt_max_pld_len];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input, char channel[]){
	dbg(channel, "Src: %hhu Dest: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dst, input->ptl, input->pld);
}

enum{
	AM_PACK=6
};

#endif
