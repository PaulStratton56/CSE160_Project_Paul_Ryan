/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;
   uses interface neighborDiscovery as nd;
   uses interface flooding as flood;

   uses interface CommandHandler;
}

implementation{
   pack sendPackage;
   uint16_t floodSequence=0;
   // Prototypes

   event void Boot.booted(){
      call AMControl.start();
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call nd.onBoot();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* incomingMsg=(pack*) payload;
         if(incomingMsg->protocol == PROTOCOL_PING){
            // if(TOS_NODE_ID!=3 || (incomingMsg->seq<55 || incomingMsg->seq>60))
            call nd.handlePingRequest(incomingMsg);
            return msg;
         }
         else if(incomingMsg->protocol == PROTOCOL_PINGREPLY){
            call nd.handlePingReply(incomingMsg);
            return msg;
         }
         else if(incomingMsg->protocol == PROTOCOL_FLOOD){
            call flood.flood(incomingMsg);
            return msg;
         }
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", incomingMsg->payload);
         return msg;
      }
      dbg(HANDLER_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT\n");
      call Sender.makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.flood(uint8_t* payload){
      dbg(GENERAL_CHANNEL, "FLOOD EVENT\n");
      floodSequence++;
      call Sender.makePack(&sendPackage,TOS_NODE_ID,TOS_NODE_ID,4,PROTOCOL_FLOOD,floodSequence,payload,PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage,AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
