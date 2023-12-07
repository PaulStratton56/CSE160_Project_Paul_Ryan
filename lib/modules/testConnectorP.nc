#include "../../includes/tcpack.h"
#include "../../includes/protocol.h"
#include "../../includes/socket.h"

module testConnectorP{
    provides interface testConnector;

    uses interface TinyController as tc;
    uses interface Timer<TMilli> as retryTimer;
}

implementation{
    uint8_t writtenBytes[412];
    uint8_t readBytes[412];
    uint8_t numBytesToRead;
    uint8_t numBytesToSend;
    uint8_t numBytesSent = 0;
    uint32_t serverID = 0;
    uint32_t clientID = 0;

    command error_t testConnector.createServer(uint8_t port, uint8_t bytes){
        numBytesToRead = bytes;
        dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Hosting testServer on port %d. Expecting %d bytes.\n", port, bytes);
        return (call tc.getPort(port, PROTOCOL_TEST_SERVER));
    }

    command error_t testConnector.createClient(uint8_t srcPort, uint8_t dest, uint8_t destPort, uint8_t bytes){
        uint8_t i;
        numBytesToSend = bytes;
        for(i = 0; i < bytes; i++){
            writtenBytes[i] = i;
            // dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Byte %d: %d\n",i+1, i);
        }
        dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Preparing to send %d bytes, ending in: %d\n", numBytesToSend, writtenBytes[numBytesToSend-1]);

        if(call tc.getPort(srcPort, PROTOCOL_TEST_CLIENT) == FAIL){
            dbg(TESTCONNECTION_CHANNEL, "ERROR (TestConnection): Port %d in use.\n");
        }

        clientID = call tc.requestConnection(dest, destPort, srcPort);
        dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Establishing connection with %d\n", dest);

        return SUCCESS;
    }

    event void tc.connected(uint32_t socketID, uint8_t sourcePTL){
        if(sourcePTL == PROTOCOL_TEST_SERVER){ 
            serverID = socketID; 
            dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Set serverID to %d\n", socketID);
        }
        if(socketID == clientID){
            numBytesSent += call tc.write(socketID, writtenBytes, numBytesToSend);
            if(numBytesSent < numBytesToSend){
                dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Connection Established. Still need to send %d bytes.\n", (numBytesToSend-numBytesSent));
                call retryTimer.startOneShot(4000);
            }
            else{
                dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Connection Established. Sent %d bytes.\n", numBytesSent);
            }
        }
    }

    event void tc.gotData(uint32_t socketID, uint8_t size){
        if(socketID == serverID){
            uint8_t i;
            call tc.read(socketID, size, readBytes);
            dbg(TESTCONNECTION_CHANNEL, "Reading %d bytes:\n", size);
            if(size == 14){
                dbg(TESTCONNECTION_CHANNEL, "Bytes: %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d\n", 
                    readBytes[0],
                    readBytes[1],
                    readBytes[2],
                    readBytes[3],
                    readBytes[4],
                    readBytes[5],
                    readBytes[6],
                    readBytes[7],
                    readBytes[8],
                    readBytes[9],
                    readBytes[10],
                    readBytes[11],
                    readBytes[12],
                    readBytes[13]);
            }
            else{
                for(i = 0; i < size; i++){
                    dbg(TESTCONNECTION_CHANNEL, "Byte %d: %d\n", i+1, readBytes[i]);
                }
            }
            numBytesToRead -= size;
            if(numBytesToRead <= 0){
                call tc.closeConnection(socketID);
                dbg(TESTCONNECTION_CHANNEL, "Bytes read. Closing Connection.\n");
            }
        }
    }
    
    event void tc.closing(uint32_t SID){
        if(SID == clientID){
            dbg(TESTCONNECTION_CHANNEL, "Obliging close request.\n");
            call tc.finishClose(SID);
        }
    }

    event void retryTimer.fired(){
        uint8_t bytesLeft = numBytesToSend - numBytesSent;
        numBytesSent += call tc.write(clientID, &(writtenBytes[numBytesSent]), bytesLeft);
        if(numBytesSent < numBytesToSend){
            dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Still need to send %d bytes.\n", (numBytesToSend-numBytesSent));
            call retryTimer.startOneShot(4000);
        }
        else{
            dbg(TESTCONNECTION_CHANNEL, "INFO (TestConnection): Sent %d bytes total.\n", numBytesSent);
        }

    }

   event void tc.wtf(uint32_t _){}

}