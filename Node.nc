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
#include "includes/floodpack.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;
   uses interface neighborDiscovery as nd;
   uses interface flooding as flood;
   uses interface PacketHandler;

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
      dbg(HANDLER_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* incomingMsg=(pack*) payload;
         
         dbg(HANDLER_CHANNEL, "Packet -> Handler");
         call PacketHandler.handle(incomingMsg);

         dbg(HANDLER_CHANNEL, "Package Payload: %s\n", incomingMsg->payload);
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
      floodpack innerPack;
      dbg(GENERAL_CHANNEL, "FLOOD EVENT\n");
      call flood.makeFloodPack(&innerPack, TOS_NODE_ID, TOS_NODE_ID, floodSequence++, 250, PROTOCOL_FLOOD, payload);
      call Sender.makePack(&sendPackage,TOS_NODE_ID,AM_BROADCAST_ADDR,4,PROTOCOL_FLOOD,floodSequence,(uint8_t*) &innerPack,PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage,AM_BROADCAST_ADDR);
   }
   event void PacketHandler.gotPing(uint8_t* _){}
   event void PacketHandler.gotflood(uint8_t* _){}
   
   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}
}
