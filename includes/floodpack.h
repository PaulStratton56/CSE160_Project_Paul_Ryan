#ifndef FLOODPACK_H
#define FLOODPACK_H


# include "protocol.h"

enum{
	FLOOD_PACKET_HEADER_LENGTH = 5,
	FLOOD_PACKET_MAX_PAYLOAD_SIZE = 20 - FLOOD_PACKET_HEADER_LENGTH,
};


typedef nx_struct floodpack{
	nx_uint16_t original_src;
	nx_uint16_t seq;
    nx_uint8_t ttl;
	nx_uint8_t protocol;
	nx_uint8_t payload[FLOOD_PACKET_MAX_PAYLOAD_SIZE];
}floodpack;

#endif
