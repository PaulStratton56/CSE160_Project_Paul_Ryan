#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"

interface neighborDiscovery{
    command void onBoot();
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
    command error_t makeNeighborPack(ndpack* packet, 
                                    uint16_t src, 
                                    uint8_t seq, 
                                    uint8_t protocol, 
                                    uint8_t* payload);
}