interface TinyController{
    command error_t getPort(uint8_t portRequest, uint8_t ptcl);
    command error_t requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort);
    command error_t closeConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort);
}