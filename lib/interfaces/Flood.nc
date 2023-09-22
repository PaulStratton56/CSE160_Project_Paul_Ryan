#include "../../includes/neighborPacket.h"

interface Flood{
    command error_t flood(uint16_t src, uint16_t dest, uint8_t seq, uint8_t reqrepProtocol, uint16_t TTL, uint8_t* message);
    command error_t handle(pack* msg);
}