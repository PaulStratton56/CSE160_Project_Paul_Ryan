#include "../../includes/socket.h"

configuration TinyControllerC{
    provides interface TinyController;
}

implementation{
    components TinyControllerP;
    TinyController = TinyControllerP.TinyController;

    components WaysenderC;
    TinyControllerP.send -> WaysenderC;

    components new HashmapC(port_t, 10) as ports;
    TinyControllerP.ports -> ports;

    components new HashmapC(socket_store_t, 255) as sockets;
    TinyControllerP.sockets -> sockets;

    components new TimerMilliC() as sendDelay;
    TinyControllerP.sendDelay -> sendDelay;

    components new TimerMilliC() as removeDelay;
    TinyControllerP.removeDelay -> removeDelay;

    components new TimerMilliC() as closeDelay;
    TinyControllerP.closeDelay -> closeDelay;

    components RandomC as Random;
    TinyControllerP.Random -> Random;

}