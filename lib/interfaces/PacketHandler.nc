interface PacketHandler{
    command error_t handle(pack* msg);
    event void gotPing(uint8_t* incomingMsg);
    event void gotflood(uint8_t* incomingMsg);
    event void gotRouted(uint8_t* incomingMsg);
    command void send(uint8_t src, 
                         uint8_t dst, 
                         uint8_t ptl, 
                         uint8_t* pld);
}