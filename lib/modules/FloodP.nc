#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/floodPacket.h"

module FloodP{
    provides interface Flood;

    uses interface SimpleSend;
    uses interface Hashmap<uint8_t> as table;
}

implementation{
    uint8_t FLOODING_SEQUENCE = 1;
    uint8_t FLOODING_TTL = 250; //If changed, also change the var in Node.nc.
    uint8_t TABLE_SIZE = 50;

    void makeFloodPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t reqrepProtocol, uint16_t seq, uint8_t* payload, uint8_t length);

    //Need to include the source...
    command error_t Flood.flood(uint16_t src, uint16_t dest, uint8_t seq, uint8_t reqrepProtocol, uint16_t TTL, uint8_t* message){
        pack floodMsg;
        uint8_t sequence;

        if(seq < 1){ sequence = FLOODING_SEQUENCE++; }
        else { sequence = seq; }
        makeFloodPack(&floodMsg, src, dest, TTL, PROTOCOL_FLOOD, reqrepProtocol, sequence, message, PACKET_MAX_PAYLOAD_SIZE);

        dbg(FLOODING_CHANNEL, "Sent '%s' to ID %d\n", (char*) message, dest);
        call SimpleSend.send(floodMsg, AM_BROADCAST_ADDR);
        return SUCCESS;
    }

    command error_t Flood.handle(pack* msg){
        floodPacket* payload = (floodPacket*) msg->payload;
        
        dbg(FLOODING_CHANNEL, "Src: %d | Dest: %d | Seq: %d | Msg: %s\n", msg->src,msg->dest,msg->seq,(char*)payload->innerPayload);

        if((msg->src == TOS_NODE_ID) || (call table.get(msg->src) >= msg->seq) || (msg->TTL <= 0)){
            dbg(FLOODING_CHANNEL, "Discarded\n");
        }
        else if(msg->dest == TOS_NODE_ID){
            if(payload->protocol == PROTOCOL_FLOODQUERY){
                char reply[] = "Back to you!";
                dbg(FLOODING_CHANNEL, "Replied\n");
                call Flood.flood(TOS_NODE_ID, msg->src, FLOODING_SEQUENCE++, PROTOCOL_FLOODREPLY, FLOODING_TTL, (uint8_t*) reply);
                call table.insert(msg->src, msg->seq);
                return SUCCESS;
            }
            else{
                dbg(FLOODING_CHANNEL, "Acknowledged Reply\n");
                call table.insert(msg->src, msg->seq);
                return SUCCESS;
            }
        }
        else{
            dbg(FLOODING_CHANNEL, "Forwarding\n");
            call Flood.flood(msg->src, msg->dest, msg->seq, payload->protocol, (msg->TTL - 1), (uint8_t*) payload->innerPayload);
            call table.insert(msg->src, msg->seq);
        }

        return SUCCESS;
    }

    void makeFloodPack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t reqrepProtocol, uint16_t seq, uint8_t* payload, uint8_t length){
        floodPacket* msg = (floodPacket*) Package->payload;
      
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;

        msg->protocol = reqrepProtocol;
        memcpy(msg->innerPayload, payload, length - sizeof(floodPacket));
   }

}