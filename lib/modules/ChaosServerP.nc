 module ChaosServerP{
    provides interface ChaosServer;
}

implementation{
    command void ChaosServer.host(){
        dbg(COMMAND_CHANNEL, "Host issued! Starting server...\n");
    }
    command void ChaosServer.printUsers(uint8_t dest){
        dbg(COMMAND_CHANNEL, "printUsers issued! Sending list to %d\n", dest);
    }

}