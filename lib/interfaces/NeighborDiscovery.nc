#include "../../includes/packet.h"

interface neighborDiscovery{
    command void onBoot();
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
}