 module ChaosClientP{
    provides interface ChaosClient;
}

implementation{
    command void ChaosClient.hello(uint8_t dest){
        dbg(COMMAND_CHANNEL, "Hello issued! Sending to %d\n",dest);
    }
    command void ChaosClient.whisper(uint8_t dest, uint8_t* payload){
        dbg(COMMAND_CHANNEL, "Whisper issued! Sending '%s' to %d\n",payload,dest);
    }
    command void ChaosClient.chat(uint8_t* payload){
        dbg(COMMAND_CHANNEL, "Chat issued! Broadcasting '%s' to all clients.\n",payload);
    }
    command void ChaosClient.goodbye(uint8_t dest){
        dbg(COMMAND_CHANNEL, "Goodbye issued! Disconnecting from %d\n",dest);
    }
}