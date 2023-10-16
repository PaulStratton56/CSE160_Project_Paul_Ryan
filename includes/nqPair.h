#ifndef NQPAIR_H
#define NQPAIR_H

typedef struct nqPair{
    uint8_t neighbor;
    float quality;
}nqPair;


void assignNQP(nqPair* target, nqPair other){
    target->neighbor = other.neighbor;
    target->quality = other.quality;
}

bool isGreaterThanNQP(nqPair left, nqPair right){
    return left.quality>right.quality;
}

#endif