#include "../../includes/tcpack.h"
#include "../../includes/protocol.h"
#include "../../includes/socket.h"

module convoP{
    provides interface convo;

    uses interface TinyController as tc;
    uses interface Timer<TMilli> as typingTimer;
}

implementation{
    port_t convoPort = 9;
    uint8_t convoProtocol = 17;
    char* openingPhrase = "Hello! How are you? The sky is blue.";
    uint32_t oneSocket;
    command void convo.onBoot(){
        call tc.getPort(convoPort,convoProtocol);
        call typingTimer.startOneShot(64000);
    }
    command void convo.startConvo(uint8_t dest){
        // call tc.requestConnection(dest,convoPort,convoPort);
    }
    event void tc.connected(uint32_t socketID){
        //if my socketID
        if(TOS_NODE_ID==1)call tc.write(oneSocket,(uint8_t*)openingPhrase,36);
    }
    event void tc.gotData(uint32_t socketID){
        //if my socket ID
        dbg(TRANSPORT_CHANNEL,"I got mail!\n");
    }
    event void typingTimer.fired(){
        if(TOS_NODE_ID==1){
            dbg(TRANSPORT_CHANNEL,"Trying to open a connection with 9\n");
            oneSocket = call tc.requestConnection(9,convoPort,convoPort);
        }
    }
}