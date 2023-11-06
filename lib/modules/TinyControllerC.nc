#include "../../includes/socket.h"

configuration TinyControllerC{
    provides interface TinyController;
}

implementation{
    components TinyControllerP;
    TinyController = TinyControllerP.TinyController;

    components PacketHandlerC;
    TinyControllerP.PacketHandler -> PacketHandlerC;

    components WaysenderC;
    TinyControllerP.send -> WaysenderC;

    components new HashmapC(port_t, 10) as ports;
    TinyControllerP.ports -> ports;

    components new HashmapC(socket_store_t*, 255) as sockets;
    TinyControllerP.sockets -> sockets;

    components RandomC as Random;
    TinyControllerP.Random -> Random;

}