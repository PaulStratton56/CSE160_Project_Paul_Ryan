#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"

interface neighborDiscovery{
    command void onBoot();
    command uint32_t getNeighbor(uint16_t i);
    command uint8_t getNeighborQuality(uint16_t i);
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command uint8_t* assembleData();
    command void printMyNeighbors();
    event void neighborUpdate();
}