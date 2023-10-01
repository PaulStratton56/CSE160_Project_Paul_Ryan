#include "../../includes/packet.h"
#include "../../includes/ndpack.h"
#include "../../includes/linkquality.h"

interface neighborDiscovery{
    command void onBoot();
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
    event void neighborUpdate();
}