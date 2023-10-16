#include "../../includes/nqPair.h"

interface Heap{
   command bool insert(nqPair node);
   command bool insertPair(uint8_t neighbor,float quality);
   command nqPair extract();
   command uint16_t size();
   command void print();
}