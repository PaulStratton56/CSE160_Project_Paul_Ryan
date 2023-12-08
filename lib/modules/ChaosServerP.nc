#include "../../includes/user.h"

module ChaosServerP{
    provides interface ChaosServer;

    uses interface Hashmap<uint32_t> as sockets;//username -> userKey -> socketID
    uses interface Hashmap<user> as users;//socketID -> user(username, lastInstruction, bytesLeft, whisperSocketID)
    uses interface TinyController as tc;
}

implementation{
    uint8_t serverPort = 11;
    uint8_t protocol = 111;
    bool server = FALSE;
    command void ChaosServer.host(){
        server = TRUE;
        dbg(CHAOS_SERVER_CHANNEL, "Host issued! Starting server...\n");
        call tc.getPort(serverPort,protocol);
    }
    command void ChaosServer.printUsers(uint8_t dest){
        dbg(CHAOS_SERVER_CHANNEL, "printUsers issued! Sending list to %d\n", dest);
    }
    uint32_t hashUsername(uint32_t* username){ //obviously very easy to engineer collisions *collisions not handled here* *expects cleared bytes final bytes for padding*
        uint32_t userKey = 0;
        int i=0;
        for(i=0;i<MAX_USERNAME_LENGTH;i++){
            userKey ^= username[i]; //xor with 4 byte window with step size 4
        }
        return userKey;
    }
    event void tc.connected(uint32_t socketID, uint8_t sourcePTL){}
    event void tc.gotData(uint32_t socketID, uint8_t length_to_read){
        if(server){
            uint8_t readBuffer[128];
            error_t e;
            user u;
            uint32_t userkey;
            uint8_t username[16];
            memset(&(readBuffer[0]),0,128);
            // dbg(CHAOS_SERVER_CHANNEL, "Got something!\n");
            if(call users.contains(socketID)){
                int i=0;
                int num_users = call users.size();
                uint32_t sid;
                uint8_t room;
                user otherUser;
                uint8_t byteCount;
                uint8_t peekBuffer[14];
                memset(&(peekBuffer[0]),0,14);
                u = call users.get(socketID);
                if(u.lastInstruction==NULL_INSTRUCTION){
                    call tc.peek(socketID,3,&(peekBuffer[0]));
                    u.lastInstruction = peekBuffer[0];
                    u.bytesLeft = 1
                                + (u.lastInstruction!=LIST_USERS_INSTRUCTION)
                                + (u.lastInstruction==HELLO_INSTRUCTION)
                                + peekBuffer[1]*(u.lastInstruction!=LIST_USERS_INSTRUCTION) 
                                + peekBuffer[2]*(u.lastInstruction==WHISPER_INSTRUCTION);
                    // dbg(CHAOS_SERVER_CHANNEL,"Peeking at [%d|%d|%d]\n",peekBuffer[0],peekBuffer[1],peekBuffer[2]);
                    // dbg(CHAOS_SERVER_CHANNEL,"instruction issued: %d | bytes left: %d\n",u.lastInstruction,u.bytesLeft);
                    if(u.lastInstruction==WHISPER_INSTRUCTION){
                        call tc.peek(socketID,length_to_read,&(peekBuffer[0]));
                        // dbg(CHAOS_SERVER_CHANNEL,"Peeking at [%d|%d|%d|%c|%c|%c|%c]\n",peekBuffer[0],peekBuffer[1],peekBuffer[2],peekBuffer[3],peekBuffer[4],peekBuffer[5],peekBuffer[6]);
                        memset(username,0,16);
                        memcpy(username,&peekBuffer[3],peekBuffer[1]);
                        userkey = hashUsername((uint32_t*)&(username[0]));
                        // dbg(CHAOS_SERVER_CHANNEL,"Username: %s, hash:%d\n",username,userkey);
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
                        call tc.updatePeek(socketID,length_to_read);
                        u.bytesLeft=0;
                        dbg(CHAOS_SERVER_CHANNEL,"Unexpected Hello from already connected user\n");
                        break;
                    case CHAT_INSTRUCTION:
                        for(i=0;i<num_users;i++){
                            sid = call users.getIndex(i);
                            room = call tc.checkWriteRoom(sid);
                            if(room<byteCount){
                                byteCount=room;
                            }
                        }
                        call tc.read(socketID,byteCount,&(readBuffer[0]));
                        for(i=0;i<num_users;i++){
                            sid = call users.getIndex(i);
                            e = call tc.write(sid,&(readBuffer[0]),byteCount);
                            if(e!=byteCount){
                                dbg(TRANSPORT_CHANNEL,"Write Problems in Chat Instruction\n");
                            }
                        }
                        dbg(CHAOS_SERVER_CHANNEL,"Sending chat to all clients\n");
                        u.bytesLeft-=byteCount;
                        break;
                    case WHISPER_INSTRUCTION:
                        room = call tc.checkWriteRoom(u.whisperSocketID);
                        if(room<byteCount){
                            byteCount=room;
                        }
                        call tc.read(socketID,byteCount,&(readBuffer[0]));
                        e = call tc.write(u.whisperSocketID,&(readBuffer[0]),byteCount);
                        if(e!=byteCount){
                            dbg(TRANSPORT_CHANNEL,"Write Problems in Whisper Instruction\n");
                        }
                        // else{
                            // dbg(CHAOS_SERVER_CHANNEL,"Whispering %d bytes to %s\n",byteCount,&((call users.get(u.whisperSocketID)).username[0]));
                        // }
                        u.bytesLeft-=byteCount;
                        break;
                    case GOODBYE_INSTRUCTION:
                        call tc.read(socketID,length_to_read,&(peekBuffer[0]));
                        u.bytesLeft=0;
                        memset(username,0,16);
                        memcpy(username,&peekBuffer[3],peekBuffer[1]);
                        userkey = hashUsername((uint32_t*)&(username[0]));
                        call sockets.remove(userkey);
                        call users.remove(socketID);
                        dbg(CHAOS_SERVER_CHANNEL,"Goodbye %s!\n",&(peekBuffer[2]));
                        break;
                    case LIST_USERS_INSTRUCTION:
                        call tc.read(socketID,length_to_read,&(readBuffer[0]));
                        for(i=0;i<num_users;i++){
                            sid = call users.getIndex(i);
                            otherUser = call users.get(sid);
                            e = call tc.write(socketID,&(otherUser.username[0]),otherUser.usernameLength);
                            if(e!=otherUser.usernameLength){
                                dbg(TRANSPORT_CHANNEL,"Write Problems in List Instruction\n");
                            }
                        }
                        u.bytesLeft=0;
                        dbg(CHAOS_SERVER_CHANNEL,"Responding with list of users\n");
                        break;
                    default:
                        dbg(CHAOS_SERVER_CHANNEL,"Nonsensical Instruction, likely buffer misalignment, from socket %d\n",socketID);
                        break;
                }
                if(u.bytesLeft==0){
                    // dbg(CHAOS_SERVER_CHANNEL,"Finished Instruction %d\n",u.lastInstruction);
                    u.lastInstruction=NULL_INSTRUCTION;
                }
                else if(u.bytesLeft<0){
                    dbg(CHAOS_SERVER_CHANNEL,"Was there a byte alignment problem? Socket %d has %d bytes left\n",socketID,u.bytesLeft);
                }
                call users.insert(socketID,u);
            }
            else{
                call tc.read(socketID,length_to_read,&(readBuffer[0]));
                if(readBuffer[0]==HELLO_INSTRUCTION){
                    u.lastInstruction=NULL_INSTRUCTION;
                    memset(&(u.username[0]),0,4*MAX_USERNAME_LENGTH);
                    memcpy(&(u.username[0]),&(readBuffer[3]),readBuffer[1]);//assuming username in first packet completely
                    userkey = hashUsername((uint32_t*)&(u.username[0]));
                    if(call sockets.contains(userkey)){
                        dbg(CHAOS_SERVER_CHANNEL, "ERROR: Username Hash Collision\n");
                    }
                    else{
                        dbg(CHAOS_SERVER_CHANNEL,"Welcome to the Server %s\n",u.username);
                        call sockets.insert(userkey,socketID);
                        call users.insert(socketID,u);
                    }
                }
                else{
                    dbg(CHAOS_SERVER_CHANNEL,"%d is not hello instruction, and user isn't known.\n",readBuffer[0]);
                }
            }
        }
    }
    event void tc.closing(uint32_t IDtoClose){
        call tc.finishClose(IDtoClose);
    }
    event void tc.wtf(uint32_t socketID){}
}