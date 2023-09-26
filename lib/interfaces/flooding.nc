#include "../../includes/packet.h"


interface flooding{
    command void initiate(uint16_t ttl, uint8_t* payload);
}