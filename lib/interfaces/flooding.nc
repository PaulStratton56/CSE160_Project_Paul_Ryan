#include "../../includes/packet.h"


interface flooding{
    command void wave();
    command void flood(uint8_t* alertPacket);
    command error_t makeFloodPack(floodpack* packet, uint16_t o_src, uint16_t p_src, uint16_t seq, uint8_t ttl, uint8_t protocol, uint8_t* payload);
}