#include "../../includes/tcpack.h"

configuration testConnectorC{
    provides interface testConnector;
}

implementation{
   components testConnectorP;
   testConnector = testConnectorP.testConnector;
   
   components TinyControllerC as tc;
   testConnectorP.tc -> tc;
   
   components new TimerMilliC() as retryTimer;
   testConnectorP.retryTimer -> retryTimer;
}