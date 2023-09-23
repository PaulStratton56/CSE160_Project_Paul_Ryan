interface PacketHandler{
    command error_t handle(pack* msg);
    event void gotPing(uint8_t* incomingMsg);
    event void gotflood(uint8_t* incomingMsg);
}