#include "../../includes/tcpack.h"

configuration convoC{
    provides interface convo;
}

implementation{
   components convoP;
   convo = convoP.convo;
   
   components new TimerMilliC() as typingTimer;
   convoP.typingTimer -> typingTimer;

   components TinyControllerC as tc;
   convoP.tc -> tc;
}