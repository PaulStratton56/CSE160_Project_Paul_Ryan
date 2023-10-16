#ifndef NQPAIR_H
#define NQPAIR_H


/* == nqPair ==
    Struct that maps a neighbor to a quality of a connection.
    Useful in constructing a topology, commonly flooded in lsps.
    neighbor: The neighbor a given node can reach.
    quality: The status of the connection between the node to the neighbor, given as a float from 0-1.
        0 means there is no connection, 1 implies a perfect connection. */
typedef struct nqPair{
    uint8_t neighbor;
    float quality;
}nqPair;

// assignNQP: Command to change a reference target nqPair's values.
void assignNQP(nqPair* target, nqPair other){
    target->neighbor = other.neighbor;
    target->quality = other.quality;
}

// isGreatherThanNQP: Returns if the first nqPair is greater than the second nqPair. 
bool isGreaterThanNQP(nqPair left, nqPair right){
    return left.quality>right.quality;
}

#endif