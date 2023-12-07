interface ChaosClient{
    command void hello(uint8_t dest);
    command void whisper(uint8_t dest, uint8_t* payload);
    command void chat(uint8_t* payload);
    command void goodbye(uint8_t dest);
}