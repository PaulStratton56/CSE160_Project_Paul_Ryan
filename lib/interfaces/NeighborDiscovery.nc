interface NeighborDiscovery{
    command error_t handle(uint8_t* neighborPack);
    command error_t setInterval(uint8_t interval);
}