#ifndef LSP_H
#define LSP_H

#include "floodpack.h"
enum{
    LSP_PACKET_HEADER_LENGTH = 3,
    LSP_PACKET_SIZE = FLOOD_PACKET_MAX_PAYLOAD_SIZE,//19
	LSP_PACKET_MAX_PAYLOAD_SIZE = LSP_PACKET_SIZE - LSP_PACKET_HEADER_LENGTH,//16
};

typedef struct lsp{
    nx_uint8_t id;
    nx_uint16_t seq;
    nx_uint8_t payload[LSP_PACKET_MAX_PAYLOAD_SIZE];
}lsp;


#endif