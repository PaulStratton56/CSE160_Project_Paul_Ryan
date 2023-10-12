#include "../../includes/packet.h"


interface flooding{
    command void initiate(uint8_t ttl, uint8_t protocol, uint8_t* payload);
}