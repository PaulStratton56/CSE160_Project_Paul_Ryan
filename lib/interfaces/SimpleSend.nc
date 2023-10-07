#include "../../includes/packet.h"

interface SimpleSend{
   command error_t send(pack msg, uint16_t dest );
   command void makePack(pack *Package, 
                        uint16_t src, 
                        uint16_t dest, 
                        uint16_t protocol, 
                        uint8_t *payload, 
                        uint8_t length);
}
