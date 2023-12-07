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

    components new HashmapC(socket_store_t, 256) as sockets;
    TinyControllerP.sockets -> sockets;

    components new QueueC(uint32_t,64) as sendQueue;
    TinyControllerP.sendQueue -> sendQueue;

    components new QueueC(tcpack,32) as receiveQueue;
    TinyControllerP.receiveQueue -> receiveQueue;

    components new QueueC(timestamp,128) as timeQueue;
    TinyControllerP.timeQueue -> timeQueue;

    components new QueueC(timestamp,128) as sendRemoveQueue;
    TinyControllerP.sendRemoveQueue -> sendRemoveQueue;

    components new QueueC(uint32_t,128) as IDstoClose;
    TinyControllerP.IDstoClose -> IDstoClose;

    components new TimerMilliC() as timeoutTimer;
    TinyControllerP.timeoutTimer -> timeoutTimer;
    
    // components new TimerMilliC() as sendDelay;
    // TinyControllerP.sendDelay -> sendDelay;

    // components new TimerMilliC() as removeDelay;
    // TinyControllerP.removeDelay -> removeDelay;

    // components new TimerMilliC() as closeDelay;
    // TinyControllerP.closeDelay -> closeDelay;

    components new TimerMilliC() as probeTimer;
    TinyControllerP.probeTimer -> probeTimer;

    components new TimerMilliC() as sendRemoveTimer;
    TinyControllerP.sendRemoveTimer -> sendRemoveTimer;

    components RandomC as Random;
    TinyControllerP.Random -> Random;

}