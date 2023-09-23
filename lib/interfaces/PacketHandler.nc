interface PacketHandler{
    command error_t handle(pack* msg);
    event void gotPingRequest(pack* incomingMsg);
    event void gotPingReply(pack* incomingMsg);
    event void gotflood(pack* incomingMsg);
}