module FloodP{
    provides interface Flood;

    uses interface SimpleSend;
}

implementation{

    command error_t Flood.flood(){
        dbg(GENERAL_CHANNEL, "Command Issued: flood.\n");
        return SUCCESS;
    }

}