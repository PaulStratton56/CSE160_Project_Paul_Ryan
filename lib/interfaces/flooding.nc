#include "../../includes/packet.h"


interface flooding{
    command void initiate(uint8_t ttl, uint8_t ptl, uint8_t* pld);
    event void gotLSP(uint8_t* payload);
}