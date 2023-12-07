
generic module HeapP(int n){
    provides interface Heap;

    uses interface Hashmap<float> as qualities;
}

implementation{
    
    uint16_t size=0;
    uint16_t MAX_HEAP_SIZE = n;
    nqPair data[n];

    uint16_t parent(uint16_t k){ return (k-1)/2;}
    uint16_t Lchild(uint16_t k){ return (2*k+1);}

    // swap: Swap heap elements a and b.
    void swap(uint16_t a, uint16_t b){
        nqPair temp;
        assignNQP(&temp,data[a]);
        assignNQP(&(data[a]),data[b]);
        assignNQP(&(data[b]),temp);
    }
 
    // fixheapDown: Given an index, swap with lower elements until heap is fixed. 
    void fixheapDown(uint16_t Index){
        uint16_t lc,rc,target;                            //siftdown approach
        lc=Lchild(Index);
        rc=lc+1;
        while(lc<size){                                 //while there is a left child
            target=Index;                               //assume index is already a local max heap
            if(isGreaterThanNQP(data[lc],data[Index])){                   //if left child is bigger, update target
                target=lc;
            }
            if(rc<size && isGreaterThanNQP(data[rc],data[target])){       //if right child is bigger than target, update target
                target=rc;
            }
            if(target!=Index){                          //if target is index, no more swaps need to be made, so exit
                swap(Index,target);                //otherwise swap and then fix heap for the target and it's progeny
                Index=target;
                lc=Lchild(Index);
                rc=lc+1;
            }
            else{
                break;
            }
        }
    }

    // fixheapUp: Given an index, swap with higher elements until the heap is fixed.
    void fixheapUp(uint16_t child){
        uint16_t adult = parent(child);
        while(child>0 && isGreaterThanNQP(data[child],data[adult])){
            swap(child,adult);
            child = adult;
            adult = parent(child);
        }
    }

    // checkMaxHeap: Returns if the current heap is a max heap or not.
    bool checkMaxHeap(){
        int i,lc,rc;
        for(i=0;i<parent(size-1)+1;i++){
            lc = Lchild(i);
            rc=lc+1;
            if(data[i].quality<data[lc].quality){
                return FALSE;
            }
            if(rc<size && data[i].quality<data[rc].quality){
                return FALSE;
            }
        }
        return TRUE;
    }
    
    // Heap.insert: insert an element into the correct position of the heap.
    command bool Heap.insert(nqPair node){
        if(size<n){
            assignNQP(&data[size],node);
            fixheapUp(size);
            size++;
            return TRUE;
        }
        return FALSE;
    }

    // Heap.insertPair: Currently heaps are hardcoded to take in neighbor quality pairs. This inserts an NQ pair.
    command bool Heap.insertPair(uint8_t neighbor,float quality){
        if(size<n){
            nqPair node;
            node.neighbor = neighbor;
            node.quality = quality;
            assignNQP(&data[size],node);
            fixheapUp(size);
            size++;
            return TRUE;
        }
        return FALSE;
    }

    // Heap.extract: Extracts and removes the top value from the heap.
    command nqPair Heap.extract(){
        nqPair max;
        if(size>0){
            assignNQP(&max,data[0]);
            size--;
            swap(0,size);
            fixheapDown(0);
            return max;
        }
        else{
            max.neighbor=0;
            max.quality = 0;
            return max;
        }
    }

    // Heap.size: Returns heap size.
    command uint16_t Heap.size(){
        return size;
    }
    
    // Heap.print: Prints the heap array. Works for NQ pair heaps only.
    command void Heap.print(){
        int i=0;
        dbg(ROUTING_CHANNEL,"%d, %d\n",size,checkMaxHeap());
        for(i=0;i<size;i++){
            dbg(ROUTING_CHANNEL,"Neighbor: %d| Quality %f\n",data[i].neighbor,data[i].quality);
        }
    }
}