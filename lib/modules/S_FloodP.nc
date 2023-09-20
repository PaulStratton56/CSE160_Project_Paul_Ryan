module S_FloodP{
    provides interface S_Flood;

    uses interface SimpleSend;
}

implementation{

    command error_t S_Flood.flood(){
        dbg(GENERAL_CHANNEL, "Command Issued: flood.\n");
        return SUCCESS;
    }

}