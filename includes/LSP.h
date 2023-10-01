#ifndef LSP_H
#define LSP_H

enum{
    LSP_PACKET_HEADER_LENGTH = 4,
	LSP_PACKET_MAX_PAYLOAD_SIZE = 15-LSP_PACKET_HEADER_LENGTH,
};

typedef struct lsp{
    nx_uint16_t id;
    nx_uint16_t seq;
    nx_uint8_t payload[LSP_PACKET_MAX_PAYLOAD_SIZE];
}lsp;


#endif