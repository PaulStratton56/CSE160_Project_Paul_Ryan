interface Waysender{
    command void send(uint8_t ttl, uint8_t dst, uint8_t ptl, uint8_t* pld);
    event void gotTCP(uint8_t* pkt);
}