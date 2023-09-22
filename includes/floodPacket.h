#ifndef FLOODPACKET_H
#define FLOODPACKET_H

typedef nx_struct floodPacket{
    nx_uint8_t protocol;
    nx_uint8_t innerPayload[0];
}floodPacket;

#endif