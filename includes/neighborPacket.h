#ifndef NEIGHBORPACKET_H
#define NEIGHBORPACKET_H

typedef nx_struct neighborPacket{
    nx_uint16_t src;
    nx_uint8_t protocol;
    nx_uint8_t payload[0];
}neighborPacket;

#endif