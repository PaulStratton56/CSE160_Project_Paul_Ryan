module BroadcastP{
    provides interface Broadcast;

    uses interface SimpleSend as sender;
}

implementation{

    command error_t Broadcast.broadcast(pack msg){
        dbg(BROADCAST_CHANNEL, "Broadcasting payload from %d\n",msg.src);
        call sender.send(msg, AM_BROADCAST_ADDR);
        return SUCCESS;
    }

}