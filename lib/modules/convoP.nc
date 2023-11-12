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
    char* openingPhrase = "\nThe world was young, the mountains green,\nNo stain yet on the Moon was seen.";
    uint8_t length = 79;
    uint32_t oneSocket;
    uint8_t incomingPhrase[79];

    command void convo.onBoot(){
        call tc.getPort(convoPort,convoProtocol);
        call typingTimer.startOneShot(64000);
    }
    command void convo.startConvo(uint8_t dest){
        oneSocket = call tc.requestConnection(dest,convoPort,convoPort);
    }
    event void tc.connected(uint32_t socketID){
        if(TOS_NODE_ID==1){
            call tc.write(oneSocket,(uint8_t*)openingPhrase,length);
        }
    }
    event void tc.gotData(uint32_t socketID,uint8_t size){
        if(size>=length){
            uint8_t* incomingData;
            // dbg(TRANSPORT_CHANNEL,"Got full message. Going to read from Socket: %d\n",socketID);
            incomingData = call tc.read(socketID, length);
            memcpy(incomingPhrase,incomingData,length);
            dbg(TRANSPORT_CHANNEL,"Reading Full message from socket %d: '%s'\n",socketID,incomingPhrase);
        }
        // else{dbg(TRANSPORT_CHANNEL,"Got Mail size %d, but not full message\n",size);}
    }
    event void typingTimer.fired(){
        if(TOS_NODE_ID==1){
            dbg(TRANSPORT_CHANNEL,"Trying to open a connection with 9\n");
            call convo.startConvo(9);
        }
    }
}