#include "../../includes/neighborPacket.h"

interface NeighborDiscovery{
    command error_t handle(neighborPacket* neighborPack);
    command error_t setInterval(uint8_t interval);
}