#include "../../includes/packet.h"

interface neighborDiscovery{
    command void onBoot();
    command void handlePingRequest(pack* pingRequest);
    command void handlePingReply(pack* pingReply);
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
}