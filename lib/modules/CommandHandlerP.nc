/**
 * @author UCM ANDES Lab
 * $Author: abeltran2 $
 * $LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
 *
 */


#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module CommandHandlerP{
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation{
    task void processCommand(){
        if(! call Queue.empty()){
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;

            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload){
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;

            //Find out which command was called and call related command
            switch(commandID){
            // A ping will have the destination of the packet as the first
            // value and the string in the remainder of the payload
                case CMD_PING:
                    dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
                    signal CommandHandler.ping(buff[0], &buff[1]);
                    break;
                    
                case CMD_NEIGHBOR_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                    signal CommandHandler.printNeighbors();
                    break;

                case CMD_LINKSTATE_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                    signal CommandHandler.printLinkState();
                    break;

                case CMD_ROUTETABLE_DUMP:
                    dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                    signal CommandHandler.printRouteTable();
                    break;

                case CMD_TEST_SERVER:
                    dbg(COMMAND_CHANNEL, "Command Type: Test Server | Port: %d\n",buff[0]);
                    signal CommandHandler.setTestServer(buff[0], buff[1]);
                    break;

                case CMD_TEST_CLIENT:
                    dbg(COMMAND_CHANNEL, "Command Type: Test Client | srcPort: %d | dest: %d | destPort: %d | bytes: %d\n",buff[0],buff[1],buff[2],buff[3]);
                    signal CommandHandler.setTestClient(buff[0],buff[1],buff[2],buff[3]);
                    break;
                    
                //A flood will only need a given string as a payload, since it broadcasts first.
                case CMD_FLOOD:
                    dbg(COMMAND_CHANNEL, "Command Type: Flood | Payload: %s\n",&buff[1]);
                    signal CommandHandler.flood(&buff[1]);
                    break;

                //Routing, however, needs a destination.
                case CMD_ROUTE:
                    dbg(COMMAND_CHANNEL, "Command Type: Route | Payload: %s\n",&buff[1]);
                    signal CommandHandler.route(buff[0], &buff[1]);
                    break;

                case CMD_CONNECT:
                    dbg(COMMAND_CHANNEL, "Command Type: Connect | Dest: %d\n",buff[0]);
                    signal CommandHandler.connect(buff[0]);
                    break;

                case CMD_DISCONNECT:
                    dbg(COMMAND_CHANNEL, "Command Type: Disconnect | From: %d\n",buff[0]);
                    signal CommandHandler.disconnect(buff[0]);
                    break;

                default:
                    dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                    break;
            }
            call Pool.put(raw_msg);
        }

        if(! call Queue.empty()){
            post processCommand();
        }
    }
    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
        if (! call Pool.empty()){
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
    }
}
