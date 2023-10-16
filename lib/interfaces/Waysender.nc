interface Waysender{
    command void send(uint8_t ttl, uint8_t dest, uint8_t protocol, uint8_t* payload);
}