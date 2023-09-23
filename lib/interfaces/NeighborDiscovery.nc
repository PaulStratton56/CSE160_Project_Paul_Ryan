#include "../../includes/packet.h"
#include "../../includes/ndpack.h"

interface neighborDiscovery{
    command void onBoot();
    command error_t handlePack(uint8_t* alertPacket);
    command void handlePingRequest(ndpack* pingRequest);
    command void handlePingReply(ndpack* pingReply);
    command uint32_t* getNeighbors();
    command uint16_t numNeighbors();
    command bool excessNeighbors();
    command void printMyNeighbors();
    command error_t makeNeighborPack(ndpack* packet, uint16_t src, uint8_t seq, uint8_t protocol, uint8_t* payload);
}