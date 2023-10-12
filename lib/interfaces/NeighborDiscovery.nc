#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"

interface neighborDiscovery{
    command void onBoot();
    event void neighborUpdate();
    command uint32_t getNeighbor(uint16_t i);
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
}