#include "../../includes/user.h"

module ChaosServerP{
    provides interface ChaosServer;

    uses interface Hashmap<uint32_t> as sockets;//username -> userKey -> socketID
    uses interface Hashmap<user> as users;//socketID -> user(username, lastInstruction, bytesLeft, whisperSocketID)
    uses interface TinyContorller as tc;
}

implementation{
    uint8_t serverPort = 11;
    uint8_t protocol = 111;
    command void ChaosServer.host(){
        dbg(COMMAND_CHANNEL, "Host issued! Starting server...\n");
        tc.getPort(serverPort,protocol);
    }
    command void ChaosServer.printUsers(uint8_t dest){
        dbg(COMMAND_CHANNEL, "printUsers issued! Sending list to %d\n", dest);
    }
    uint32_t hashUsername(uint32_t* username){ //obviously very easy to engineer collisions *collisions not handled here* *expects cleared bytes final bytes for padding*
        uint32_t userKey = 0;
        int i=0;
        for(i=0;i<MAX_USERNAME_LENGTH;i++){
            userKey ^= username[i]; //xor with 4 byte window with step size 4
        }
        return userKey;
    }
    event void connected(uint32_t socketID, uint8_t sourcePTL){}
    event void gotData(uint32_t socketID, uint8_t length_to_read){
        uint8_t readBuffer[128];
        error_t e;
        if(call users.contains(socketID)){
            uint32_t userkey;
            user u;
            uint8_t byteCount=128;
            uint8_t peekBuffer[14];
            u = call users.get(socketID);
            if(u.lastInstruction==NULL_INSTRUCTION){
                tc.peek(socketID,3,&(peekBuffer[0]));
                u.lastInstruction = peekBuffer[0];
                u.bytesLeft = 1
                            + peekBuffer[1]*(u.lastInstruction!=LIST_USERS_INSTRUCTION) 
                            + (u.lastInstruction==HELLO_INSTRUCTION)
                            + peekBuffer[2]*(u.lastInstruction==WHISPER_INSTRUCTION);
                if(u.lastInstruction==WHISPER_INSTRUCTION){
                    tc.peek(socketID,length_to_read,&(peekBuffer[0]));
                    userkey = hashUsername((uint32_t*)&(peekBuffer[3]));
                    if(call sockets.contains(userkey)){
                        u.whisperSocketID = call sockets.get(userkey);
                    }
                    else{
                        dbg(CHAOS_SERVER_CHANNEL,"Can't whisper to non-client\n");
                    }
                }
                else{
                    u.whisperSocketID=0;
                }
            }
            byteCount = u.bytesLeft;
            switch(u.lastInstruction){
                case HELLO_INSTRUCTION:
                    tc.updatePeek(socketID,length_to_read);
                    u.bytesLeft=0;
                    dbg(CHAOS_SERVER_CHANNEL,"Unexpected Hello from already connected user\n");
                    break;
                case CHAT_INSTRUCTION:
                    int i=0;
                    int num_users = users.size();
                    uint32_t sid;
                    uint8_t room;
                    for(i=0;i<num_users;i++){
                        sid = users.getIndex(i);
                        room = call tc.checkWriteRoom(sid);
                        if(room<byteCount){
                            byteCount=room;
                        }
                    }
                    tc.read(socketID,byteCount,&(readBuffer[0]));
                    for(i=0;i<num_users;i++){
                        sid = users.getIndex(i);
                        e = tc.write(sid,&(readBuffer[0]),byteCount);
                        if(e!=SUCCESS){
                            dbg(TRANSPORT_CHANNEL,"Write Problems in Chat Instruction\n");
                        }
                    }
                    u.bytesLeft-=byteCount;
                    break;
                case WHISPER_INSTRUCTION:
                    uint8_t room = call tc.checkWriteRoom(u.whisperSocketID);
                    if(room<byteCount){
                        byteCount=room;
                    }
                    tc.read(socketID,byteCount,&(readBuffer[0]));
                    e = tc.write(u.whisperSocketID,&(readBuffer[0]),byteCount);
                    if(e!=SUCCESS){
                        dbg(TRANSPORT_CHANNEL,"Write Problems in Whisper Instruction\n");
                    }
                    u.bytesLeft-=byteCount;
                    break;
                case GOODBYE_INSTRUCTION:
                    tc.read(socketID,length_to_read,&(peekBuffer[0]));
                    u.bytesLeft=0;
                    userkey = hashUsername((uint32_t*)&(peekBuffer[2]));
                    call sockets.remove(userkey);
                    call users.remove(socketID);
                    dbg(CHAOS_SERVER_CHANNEL,"Removed user %s\n",&(peekBuffer[2]));
                    break;
                case LIST_USERS_INSTRUCTION:
                    int i=0;
                    int num_users = call users.size();
                    uint32_t sid;
                    user otherUser;
                    tc.read(socketID,length_to_read,&(readBuffer[0]));
                    for(i=0;i<num_users;i++){
                        sid = call users.getIndex(i);
                        otherUser = call users.get(sid);
                        e =tc.write(socketID,&(otherUser.username[0]),otherUser.usernameLength);
                        if(e!=SUCCESS){
                            dbg(TRANSPORT_CHANNEL,"Write Problems in List Instruction\n");
                        }
                    }
                    u.bytesLeft=0;
                    break;
                default:
                    dbg(CHAOS_SERVER_CHANNEL,"Nonsensical Instruction, likely buffer misalignment, from socket %d\n",socketID);
                    break;
            }
            if(u.bytesLeft==0){
                u.lastInstruction=NULL_INSTRUCTION;
            }
            else if(u.bytesLeft<0){
                dbg(CHAOS_SERVER_CHANNEL,"Was there a byte alignment problem? Socket %d has %d bytes left\n",sockedID,u.bytesLeft);
            }
            users.insert(socketID,u);
        }
        else{
            tc.read(socketID,14,&(readBuffer[0]));
            if(readBuffer[0]==HELLO_INSTRUCTION){
                memcpy(&(u.username[0]),&(readBuffer[3]),readBuffer[1])//assuming username in first packet completely
                userkey = hashUsername((uint32_t*)&(u.username[0]));
                if(call sockets.contains(userkey)){
                    dbg(CHAOS_SERVER_CHANNEL, "ERROR: Username Hash Collision\n");
                }
                else{
                    call sockets.insert(userkey,socketID);
                    call users.insert(socketID,);
                }
            }
            else{
                dbg(CHAOS_SERVER_CHANNEL,"Not hello instruction\n");
            }
        }
    }
    event void closing(uint32_t IDtoClose){
        command tc.finishClose(IDtoClose);
    }
    event void wtf(uint32_t socketID){}
}