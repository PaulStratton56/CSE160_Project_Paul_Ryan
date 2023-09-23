#ifndef NDPACK_H
#define NDPACK_H


# include "protocol.h"

enum{
	ND_PACKET_HEADER_LENGTH = 4,
	ND_PACKET_MAX_PAYLOAD_SIZE = 20 - ND_PACKET_HEADER_LENGTH,
};


typedef nx_struct ndpack{
	nx_uint16_t src;
	nx_uint8_t seq;
	nx_uint8_t protocol;
	nx_uint8_t payload[ND_PACKET_MAX_PAYLOAD_SIZE];
}ndpack;

#endif
