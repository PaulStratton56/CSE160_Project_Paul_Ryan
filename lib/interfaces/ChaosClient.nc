interface ChaosClient{
    command void hello(uint8_t dest, uint8_t* username, uint8_t userLength);
    command void whisper(uint8_t dest, uint8_t msgLen, uint8_t* payload, uint8_t userLen);
    command void chat(uint8_t* payload, uint8_t msgLen);
    command void goodbye(uint8_t dest);
    command void printUsers(uint8_t dest);
}
