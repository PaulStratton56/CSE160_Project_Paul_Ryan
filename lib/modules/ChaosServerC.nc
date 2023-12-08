#include "../../includes/user.h"

configuration ChaosServerC{
    provides interface ChaosServer;
}

implementation{
    components ChaosServerP;
    ChaosServer = ChaosServerP.ChaosServer;

    components new HashmapC(uint32_t, 64) as sockets;
    ChaosServerP.sockets -> sockets;

    components new HashmapC(user, 64) as users;
    ChaosServerP.users -> users;

    components TinyControllerC as tc;
    ChaosServerP.tc -> tc;
}