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
    uint8_t incomingLength;

    // hello: [instruction|usernameLength|port|username|\00]
    // ex: ((0<<6)+(clientPort))7icy_wind\00
    // chat: [instruction|msg|\00]
    // ex: (1)HiAll!\00
    // whisper: [instruction|usernameLength|targetUser|msg|\00]
    // ex: (2+(8<<2))gandlehelloWorld\00 (from icy_wind)
    // goodbye: [instruction|usernameLength|username|\00]
    // ex: (3+(8<<2))icy_wind\00
    // listuser: 4

    /* == hello == 
        Called when a client is told to connect to the destination server.
        Sets the username and usernameLength to whatever Node tells it to.
        Establishes a connection via TinyController. */
    command void ChaosClient.hello(uint8_t dest, uint8_t* user, uint8_t userLength){
        error_t result = FAIL;
        uint8_t bytesToSend = 3+userLength;
        uint8_t helloMessage[bytesToSend];

        dbg(COMMAND_CHANNEL, "Connecting to server %d...\n",dest);

        //Copy the username into the client interface.
        memcpy(username, user, userLength);
        usernameLength = userLength;

        //Construct the hello message to send to the server.
        helloMessage[0] = 0;
        helloMessage[1] = userLength;
        helloMessage[2] = clientPort;
        memcpy(&helloMessage[3], user, userLength);

        //Continue asking for a port until TC complies.
        while(result == FAIL){
            result = call TC.getPort(clientPort, 10);
        }

        //Request a connection with the server.
        clientSocket = call TC.requestConnection(dest, 11, clientPort);

        //Keep shoving the helloMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        //     bytesToSend -= call TC.write(clientSocket, &helloMessage[3 + (usernameLength-bytesToSend)], bytesToSend);
        // }

        dbg(COMMAND_CHANNEL, "Sent |%d|%d|%d|%s.\n",helloMessage[0],helloMessage[1],helloMessage[2],&helloMessage[3]);

        dbg(COMMAND_CHANNEL, "Welcome, %s.\n",username);
    }

    /* == chat ==
        Called when a client wants to send a message to all currently connected clients.
        Accepts and modifies a payload, then sends it to the server for distribution. */
    command void ChaosClient.chat(uint8_t* payload, uint8_t msgLen){
        uint8_t bytesToSend = 2+msgLen;
        uint8_t chatMessage[bytesToSend];

        dbg(COMMAND_CHANNEL, "Posting '%s'...\n",payload);
        
        memcpy(outboundMail, payload, bytesToSend);
        outboundLength = msgLen;

        chatMessage[0] = 1;
        chatMessage[1] = msgLen;
        memcpy(&chatMessage[2], payload, msgLen);

        //Keep shoving the chatMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        //     bytesToSend -= call TC.write(clientSocket, &chatMessage[2 + (msgLen-bytesToSend)], bytesToSend);
        // }

        dbg(COMMAND_CHANNEL, "Sent |%d|%d|%s.\n", chatMessage[0], chatMessage[1], &chatMessage[2]);

    }

    /* == whisper ==
        Called when a client wants to whisper a given message to another client.
        Accepts a payload, and sets the format of the message before sending. */
    command void ChaosClient.whisper(uint8_t dest, uint8_t msgLen, uint8_t* payload, uint8_t userLen){
        uint8_t bytesToSend = 3+msgLen+userLen;
        uint8_t whisperMessage[bytesToSend];
        uint8_t user[userLen];
        uint8_t msg[msgLen];

        memcpy(user, &payload[msgLen], userLen);
        memcpy(msg, payload, msgLen);

        
        memcpy(outboundMail, payload, bytesToSend);
        outboundLength = msgLen;

        whisperMessage[0] = 2;
        whisperMessage[1] = userLen;
        whisperMessage[2] = msgLen;
        memcpy(&whisperMessage[3], user, userLen);
        memcpy(&whisperMessage[3+userLen], msg, msgLen);

        //Keep shoving the chatMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        //     bytesToSend -= call TC.write(clientSocket, &chatMessage[2 + (msgLen-bytesToSend)], bytesToSend);
        // }

        {
        uint8_t pMessage[msgLen+1];
        uint8_t pUser[userLen+1];
        memcpy(pMessage, &whisperMessage[3+userLen], msgLen);
        memcpy(pUser, &whisperMessage[3], userLen);
        pMessage[msgLen] = '\00';
        pUser[userLen] = '\00';
        dbg(COMMAND_CHANNEL, "Whispering to %s (node %d): '%s'...\n", user, dest, pMessage);
        dbg(COMMAND_CHANNEL, "Sent |%d|%d|%d|%s|%s.\n", whisperMessage[0], whisperMessage[1], whisperMessage[2], pUser, pMessage);
        }
        
    }

    /* == goodbye == 
        Called when a client is told to disconnect from its server. */
    command void ChaosClient.goodbye(uint8_t dest){
        uint8_t bytesToSend = usernameLength+2;
        uint8_t goodbyeMessage[bytesToSend];
        dbg(COMMAND_CHANNEL, "Logging out from server %d...\n",dest);

        goodbyeMessage[0] = 3;
        goodbyeMessage[1] = usernameLength;
        memcpy(&goodbyeMessage[2],username,usernameLength);

        //Keep shoving the goodbyeMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        //     bytesToSend -= call TC.write(clientSocket, &goodbyeMessage[2 + (usernameLength-bytesToSend)], bytesToSend);
        // }

        // call TC.closeConnection(clientSocket);
        {
            uint8_t* pUser[usernameLength+1];
            memcpy(pUser, &goodbyeMessage[2], usernameLength);
            pUser[usernameLength] = '\00';
            dbg(COMMAND_CHANNEL, "Sent |%d|%d|%s\n.",goodbyeMessage[0],goodbyeMessage[1],pUser);
            dbg(COMMAND_CHANNEL, "Goodbye, %s.\n", pUser);
        }
    }

    /* == printUsers ==
        Called when a client wants to get a list of users from the server.
        Sends the simplest of the messages to the server. */
    command void ChaosClient.printUsers(uint8_t dest){
        uint8_t printUsersMessage[1];
        uint8_t bytestoSend = 1;

        printUsersMessage[0] = 4;

        //Keep shoving the printUsersMessage into the buffer until it's all there. (Should only be once)
        //Doesn't work until there's a server to send to
        // while(bytesToSend > 0){
        //     bytesToSend -= call TC.write(clientSocket, printUsersMessage, bytesToSend);
        // }

        dbg(COMMAND_CHANNEL, "Send |%d|.\n", printUsersMessage[0]);
        dbg(COMMAND_CHANNEL, "Getting users!\n");
    }

    event void TC.gotData(uint32_t socketID, uint8_t length){
        if(socketID == clientSocket){
            dbg(COMMAND_CHANNEL, "Got something! I'm not programmed to understand what it is yet though...\n");
        }
    }

    event void TC.closing(uint32_t IDtoClose){
        call TC.finishClose(IDtoClose);
    }

    event void TC.connected(uint32_t socketID, uint8_t sourcePTL){}
    event void TC.wtf(uint32_t socketID){}
}