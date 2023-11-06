interface TinyController{
    command error_t getPort(uint8_t portRequest, uint8_t ptcl);
    command void requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort);
}