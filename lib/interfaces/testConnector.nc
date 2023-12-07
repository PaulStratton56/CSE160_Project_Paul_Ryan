#include "../../includes/tcpack.h"

interface testConnector{
    command error_t createServer(uint8_t port, uint8_t bytes);
    command error_t createClient(uint8_t srcPort, uint8_t dest, uint8_t destPort, uint8_t bytes);
}