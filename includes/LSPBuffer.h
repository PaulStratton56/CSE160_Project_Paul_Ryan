#ifndef LSPBUFFER_H
#define LSPBUFFER_H

typedef struct lspBuffer{
    uint8_t src;
    uint16_t seq;
    uint8_t size;
    uint32_t time;
    uint8_t pairs[128];
}lspBuffer;

#endif