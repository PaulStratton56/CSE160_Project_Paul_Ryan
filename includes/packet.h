//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


# include "protocol.h"
#include "channels.h"

enum{
	PACKET_HEADER_LENGTH = 5,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH //23
};


typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input, char channel[]){
	dbg(channel, "Src: %hhu Dest: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};

#endif
