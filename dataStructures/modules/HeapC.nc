
#include "../../includes/channels.h"
#include "../../includes/nqPair.h"

generic configuration HeapC(int n){
   provides interface Heap;
}

implementation{
    components new HeapP(n);
    Heap = HeapP.Heap;

    components new HashmapC(float, 32) as qualities;
    HeapP.qualities -> qualities;
}