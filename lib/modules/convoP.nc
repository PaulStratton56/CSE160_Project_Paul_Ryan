#include "../../includes/tcpack.h"
#include "../../includes/protocol.h"
#include "../../includes/socket.h"

module convoP{
    provides interface convo;

    uses interface TinyController as tc;
    uses interface Timer<TMilli> as typingTimer;
}

implementation{
    uint8_t a = 13;
    uint8_t b = 16;
    uint8_t c = 23;
    port_t convoPort = 9;
    uint8_t convoProtocol = 17;
    char* openingPhrase1 = "\n\nThe world was young, the mountains green,\nNo stain yet on the Moon was seen.\n";
    uint8_t length1 = 79;
    char* openingPhrase2 = "\nNo words were laid on stream or stone\nWhen Durin woke and walked alone.\n";
    uint8_t length2 = 73;
    char* openingPhrase3 = "\nHe named the nameless hills and dells;\nHe drank from yet untasted wells;\n";
    uint8_t length3 = 74;
    uint32_t oneSocket; //He stooped and looked in Mirrormere, And saw a crown of stars appear, As gems upon a silver thread, Above the shadow of his head.
    uint32_t serverID = 0;
    uint8_t incomingPhrase[79];

    command void convo.onBoot(){
        call tc.getPort(convoPort,convoProtocol);
        call typingTimer.startOneShot(64000);
    }
    command void convo.startConvo(uint8_t dest){
        oneSocket = call tc.requestConnection(dest,convoPort,convoPort);
    }
    event void tc.connected(uint32_t socketID, uint8_t sourcePTL){
        if(socketID==oneSocket && sourcePTL == convoProtocol){
            if(TOS_NODE_ID==a){
                call tc.write(oneSocket,(uint8_t*)openingPhrase1,length1);
            }
            else if(TOS_NODE_ID==b){
                call tc.write(oneSocket,(uint8_t*)openingPhrase2,length2);
            }
            else if(TOS_NODE_ID==c){
                call tc.write(oneSocket,(uint8_t*)openingPhrase3,length3);
            }
        }
        else{
            if(sourcePTL == convoProtocol){
                serverID = socketID;
            }
            dbg(TRANSPORT_CHANNEL,"Signaled socket: %d | Expected Socket: %d\n",socketID,oneSocket);
        }
    }
    event void tc.gotData(uint32_t socketID,uint8_t size){
        if(socketID == serverID){
            if(TOS_NODE_ID==a){
                if(size>=length3){
                    // dbg(TRANSPORT_CHANNEL,"Got full message. Going to read from Socket: %d\n",socketID);
                    call tc.read(socketID, length3,&(incomingPhrase[0]));
                    dbg(TRANSPORT_CHANNEL,"Reading Full message from socket %d: '%s'\n",socketID,incomingPhrase);
                    call tc.closeConnection(socketID);
                }
            }
            else if(TOS_NODE_ID==b){
                if(size>=length1){
                    // dbg(TRANSPORT_CHANNEL,"Got full message. Going to read from Socket: %d\n",socketID);
                    call tc.read(socketID, length1,&(incomingPhrase[0]));
                    dbg(TRANSPORT_CHANNEL,"Reading Full message from socket %d: '%s'\n",socketID,incomingPhrase);
                    call tc.closeConnection(socketID);
                }
                else{
                    dbg(TRANSPORT_CHANNEL, "Not reading. Need %d more bytes.\n", length1-size);
                }
            }
            else if(TOS_NODE_ID==c){
                if(size>=length2){
                    // dbg(TRANSPORT_CHANNEL,"Got full message. Going to read from Socket: %d\n",socketID);
                    call tc.read(socketID, length2,&(incomingPhrase[0]));
                    dbg(TRANSPORT_CHANNEL,"Reading Full message from socket %d: '%s'\n",socketID,incomingPhrase);
                    call tc.closeConnection(socketID);
                }
            }
        }
    }

    event void typingTimer.fired(){
        if(TOS_NODE_ID==a){
            dbg(TRANSPORT_CHANNEL,"Trying to open a connection with %d\n", b);
            call convo.startConvo(b);
        }
        else if(TOS_NODE_ID==b){
            dbg(TRANSPORT_CHANNEL,"Trying to open a connection with %d\n",c);
            call convo.startConvo(c);
        }
        else if(TOS_NODE_ID==c){
            dbg(TRANSPORT_CHANNEL,"Trying to open a connection with %d\n",a);
            call convo.startConvo(a);
        }
    }
    event void tc.closing(uint32_t SID){
        call tc.finishClose(SID);
    }
    event void tc.wtf(uint32_t _){}
}