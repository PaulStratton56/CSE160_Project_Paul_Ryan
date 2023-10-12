module WaysenderP{
    provides interface Waysender;

    uses interface SimpleSend as sender;
    uses interface Wayfinder as router;
    uses interface PacketHandler;
}

implementation{

    command error_t Waysender.send(){
        //Called when a routing packet wants to be sent!
        //Sends a packet using a routing table.

    }

    task forwardPackets(){
        //Posted when PacketHandler signals a routed packet.
        //Forwards the packet according to the routing table.


    }

}