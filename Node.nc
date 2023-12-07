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
   uses interface Wayfinder;
   uses interface Waysender as router;
   uses interface TinyController as TCP;
   uses interface PacketHandler;
   uses interface convo;
   uses interface testConnector;

   uses interface CommandHandler;
   uses interface ChaosClient;
   uses interface ChaosServer;
}

implementation{
   pack sendPackage;

   event void Boot.booted(){
      call AMControl.start();
      // dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         // dbg(GENERAL_CHANNEL, "Radio On\n");

         //When done booting, start the ND Ping timer.
         call nd.onBoot();
         call Wayfinder.onBoot();
         // call convo.onBoot();
         // call TCP.getPort(1,69);

      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(HANDLER_CHANNEL, "Packet Received\n");
      // if(((pack*)payload)->ptl==PROTOCOL_ROUTING)dbg(ROUTING_CHANNEL, "Got Routing Packet from: %d\n",((pack*)payload)->src);
      if(len==sizeof(pack)){         
         
         //Pass the packet off to a separate packet handler module.
         dbg(HANDLER_CHANNEL, "Packet -> Handler");
         call PacketHandler.handle((pack*) payload);

         return msg;
      }
      dbg(HANDLER_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT\n");
      call PacketHandler.send(TOS_NODE_ID, destination, PROTOCOL_PING, payload);
   }

   event void PacketHandler.gotPing(uint8_t* _){}
   event void PacketHandler.gotflood(uint8_t* _){}
   event void flood.gotLSP(uint8_t* _){}
   event void PacketHandler.gotRouted(uint8_t* _){}
   
   event void nd.neighborUpdate(){}
   //Command implementation of flooding
   event void CommandHandler.flood(uint8_t* payload){
      dbg(GENERAL_CHANNEL, "FLOOD EVENT\n");
      call flood.initiate(255, PROTOCOL_FLOOD, payload);  
   }

   event void CommandHandler.route(uint8_t dest, uint8_t* payload){
      dbg(GENERAL_CHANNEL, "ROUTE EVENT\n");
      call router.send(255, dest, PROTOCOL_ROUTING, payload);
   }
   
   event void CommandHandler.connect(uint8_t dest){
      dbg(GENERAL_CHANNEL, "CONNECT EVENT\n");
      call TCP.requestConnection(dest, 1, 1);
   }
   
   event void CommandHandler.disconnect(uint8_t dest){
      dbg(GENERAL_CHANNEL, "DISCONNECT EVENT\n");
      call TCP.closeConnection((1<<24) + (1<<16) + (TOS_NODE_ID<<8) + dest);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t port, uint8_t bytes){
      dbg(GENERAL_CHANNEL, "TEST_SERVER EVENT\n");
      call testConnector.createServer(port, bytes);
   }

   event void CommandHandler.setTestClient(uint8_t srcPort, uint8_t dest, uint8_t destPort, uint8_t bytes){
      dbg(GENERAL_CHANNEL, "TEST_CLIENT EVENT\n");
      call testConnector.createClient(srcPort, dest, destPort, bytes);

   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void CommandHandler.host(){
      call ChaosServer.host();
   }

   event void CommandHandler.printUsers(uint8_t dest){
      call ChaosServer.printUsers(dest);
   }

   event void CommandHandler.hello(uint8_t dest){
      call ChaosClient.hello(dest);
   }

   event void CommandHandler.goodbye(uint8_t dest){
      call ChaosClient.goodbye(dest);
   }

   event void CommandHandler.whisper(uint8_t dest, uint8_t* payload){
      call ChaosClient.whisper(dest, payload);
   }

   event void CommandHandler.chat(uint8_t* payload){
      call ChaosClient.chat(payload);
   }
   
   event void router.gotTCP(uint8_t* _){}

   event void TCP.connected(uint32_t _, uint8_t __){}
   event void TCP.gotData(uint32_t _,uint8_t __){}
   event void TCP.closing(uint32_t _){}
   event void TCP.wtf(uint32_t _){}
}
