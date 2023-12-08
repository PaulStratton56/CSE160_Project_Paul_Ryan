#include "../includes/user.h"

module ChaosClientP{
    provides interface ChaosClient;

    uses interface TinyController as TC;
}

implementation{
    uint32_t clientSocket;
    uint8_t username[64];
    uint8_t usernameLength;
    uint8_t clientPort = 10;
    uint8_t outboundMail[256];
    uint8_t outboundLength;
    uint8_t incomingMail[256];
    uint8_t fullIncomingLength;
    uint8_t receivedUntil = 0;

    /* == hello == 
        Called when a client is told to connect to the destination server.
        Sets the username and usernameLength to whatever Node tells it to.
        Establishes a connection via TinyController. */
    command void ChaosClient.hello(uint8_t dest, uint8_t* newUser, uint8_t userLength){
        error_t result = FAIL;
        uint8_t bytesToSend = 3+userLength;
        uint8_t helloMessage[bytesToSend];

        //Copy the username into the client interface.
        memcpy(username, newUser, userLength);
        usernameLength = userLength;

        //Construct the hello message to send to the server.
        helloMessage[0] = HELLO_INSTRUCTION;
        helloMessage[1] = userLength;
        helloMessage[2] = clientPort;
        memcpy(&(helloMessage[3]), newUser, userLength);

        //Continue asking for a port until TC complies.
        while(result == FAIL){
            result = call TC.getPort(clientPort, 10);
        }

        //Request a connection with the server.
        clientSocket = call TC.requestConnection(dest, 11, clientPort);

        //Store the message for when we're connected.
        //Need to wait for connected state, which will be signaled.
        memcpy(outboundMail, helloMessage, bytesToSend);
        outboundLength = bytesToSend;

        dbg(CHAOS_CLIENT_CHANNEL, "Connecting to server %d...\n",dest);
    }

    /* == chat ==
        Called when a client wants to send a message to all currently connected clients.
        Accepts and modifies a payload, then sends it to the server for distribution. */
    command void ChaosClient.chat(uint8_t* payload, uint8_t msgLen){
        uint8_t bytesToSend = 2+msgLen;
        uint8_t chatMessage[bytesToSend];

        dbg(CHAOS_CLIENT_CHANNEL, "Posting Chat '%s'...\n",payload);
        
        // memcpy(outboundMail, payload, bytesToSend);
        // outboundLength = msgLen;

        chatMessage[0] = CHAT_INSTRUCTION;
        chatMessage[1] = msgLen;
        memcpy(&chatMessage[2], payload, msgLen);

        //Keep shoving the chatMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        bytesToSend -= call TC.write(clientSocket, &(chatMessage[2 + (msgLen-bytesToSend)]), bytesToSend);
        // }

        // dbg(CHAOS_CLIENT_CHANNEL, "Sent |%d|%d|%s.\n", chatMessage[0], chatMessage[1], &chatMessage[2]);

    }

    /* == whisper ==
        Called when a client wants to whisper a given message to another client.
        Accepts a payload, and sets the format of the message before sending. */
    command void ChaosClient.whisper(uint8_t dest, uint8_t userLen, uint8_t msgLen, uint8_t* payload){
        uint8_t bytesToSend = 3+msgLen+userLen;
        uint8_t whisperMessage[bytesToSend];
        uint8_t targetUser[userLen];
        uint8_t msg[msgLen];
        
        memcpy(targetUser,payload,userLen);
        memcpy(msg,&payload[userLen],msgLen);

        // memcpy(outboundMail, payload, bytesToSend);
        // outboundLength = userLen+msgLen;

        whisperMessage[0] = WHISPER_INSTRUCTION;
        whisperMessage[1] = userLen;
        whisperMessage[2] = msgLen;
        memcpy(&whisperMessage[3], payload, userLen);
        memcpy(&whisperMessage[3+userLen], &payload[userLen], msgLen);

        //Keep shoving the chatMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
            bytesToSend -= call TC.write(clientSocket, &whisperMessage[3 + (userLen+msgLen-bytesToSend)], bytesToSend);
        // }

        {
            uint8_t pUser[userLen+1];
            uint8_t pMessage[msgLen+1];
            memcpy(pUser, targetUser, userLen);
            memcpy(pMessage, msg, msgLen);
            pUser[userLen] = '\00';
            pMessage[msgLen] = '\00';
            dbg(CHAOS_CLIENT_CHANNEL, "Whispering to %s (node %d): '%s'...\n", targetUser, dest, pMessage);
            // dbg(CHAOS_CLIENT_CHANNEL, "Sent |%d|%d|%d|%s|%s.\n", whisperMessage[0], whisperMessage[1], whisperMessage[2], pUser, pMessage);
        }
        
    }

    /* == goodbye == 
        Called when a client is told to disconnect from its server. */
    command void ChaosClient.goodbye(uint8_t dest){
        uint8_t bytesToSend = usernameLength+2;
        uint8_t goodbyeMessage[bytesToSend];

        goodbyeMessage[0] = GOODBYE_INSTRUCTION;
        goodbyeMessage[1] = usernameLength;
        memcpy(&goodbyeMessage[2],username,usernameLength);

        //Keep shoving the goodbyeMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
            bytesToSend -= call TC.write(clientSocket, &goodbyeMessage[2 + (usernameLength-bytesToSend)], bytesToSend);
        // }

        call TC.closeConnection(clientSocket);

        {
            uint8_t pUser[usernameLength+1];
            memcpy(pUser, &goodbyeMessage[2], usernameLength);
            pUser[usernameLength] = '\00';
            // dbg(CHAOS_CLIENT_CHANNEL, "Sent |%d|%d|%s\n.",goodbyeMessage[0],goodbyeMessage[1],pUser);
            // dbg(CHAOS_CLIENT_CHANNEL, "Goodbye from %s.\n", pUser);
            dbg(CHAOS_CLIENT_CHANNEL, "Logging out. Goodbye from %s\n",pUser);
        }
    }

    /* == printUsers ==
        Called when a client wants to get a list of users from the server.
        Sends the simplest of the messages to the server. */
    command void ChaosClient.printUsers(uint8_t dest){
        uint8_t printUsersMessage[1];
        uint8_t bytesToSend = 1;

        printUsersMessage[0] = LIST_USERS_INSTRUCTION;

        //Keep shoving the printUsersMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
            bytesToSend -= call TC.write(clientSocket, printUsersMessage, bytesToSend);
        // }

        dbg(CHAOS_CLIENT_CHANNEL, "Send |%d|.\n", printUsersMessage[0]);
        dbg(CHAOS_CLIENT_CHANNEL, "Getting users!\n");
    }

    event void TC.gotData(uint32_t socketID, uint8_t length){
        if(socketID == clientSocket){
            call TC.read(clientSocket, length, &incomingMail[receivedUntil]);
            if(receivedUntil == 0){ //new message
                switch(incomingMail[0]){
                    case(CHAT_INSTRUCTION):
                        fullIncomingLength = incomingMail[1] + 2;
                        break;
                    case(WHISPER_INSTRUCTION):
                        fullIncomingLength = 3 + incomingMail[1] + incomingMail[2];
                        break;
                    case(LIST_USERS_INSTRUCTION):
                        fullIncomingLength = incomingMail[1] + 2;
                        break;
                }
            }
            receivedUntil += length;
            if(receivedUntil >= fullIncomingLength){ //Full message
                uint8_t printedMessage[fullIncomingLength+1];
                receivedUntil = 0;

                memcpy(printedMessage, incomingMail, fullIncomingLength);
                printedMessage[fullIncomingLength] = '\00';
                dbg(CHAOS_CLIENT_CHANNEL, "Message received: %s\n",printedMessage);
                memset(&(incomingMail[0]), 0, 256);
            }
            else{
                dbg(CHAOS_CLIENT_CHANNEL, "Still missing %d bytes. Expecting %d, have %d!!!\n", (fullIncomingLength-receivedUntil),fullIncomingLength,receivedUntil);
            }
        }
    }

    event void TC.closing(uint32_t IDtoClose){
        call TC.finishClose(IDtoClose);
    }

    event void TC.connected(uint32_t socketID, uint8_t sourcePTL){
        if(sourcePTL == PROTOCOL_CHAOS_CLIENT && socketID == clientSocket){
            call TC.write(clientSocket, outboundMail, outboundLength);
            // dbg(CHAOS_CLIENT_CHANNEL, "Sent |%d|%d|%d|%s.\n",outboundMail[0],outboundMail[1],outboundMail[2],&outboundMail[3]);
        }
        // else{
        //     dbg(CHAOS_CLIENT_CHANNEL, "Not my connection.\n");
        // }

    }

    event void TC.wtf(uint32_t socketID){}
}