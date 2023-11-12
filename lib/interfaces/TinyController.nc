interface TinyController{
    command error_t getPort(uint8_t portRequest, uint8_t ptcl);
    command uint32_t requestConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort);
    command error_t closeConnection(uint8_t dest, uint8_t destPort, uint8_t srcPort);
    command error_t write(uint32_t socketID, uint8_t* payload, uint8_t length);
    command uint8_t* read(uint32_t socketID,uint8_t length);
    event void connected(uint32_t socketID);
    event void gotData(uint32_t socketID,uint8_t length);
}