#ifndef LINKQUALITY_H
#define LINKQUALITY_H

/*
== linkquality ==
This struct contains the parameters of a given connection in a network.
Quality: float signifying the quality of any given link.
If this falls below allowedQuality in NeighborDiscoveryP, the link is too unreliable to be considered.
Recent: bool representing whether an incoming packet is recent or not (used to update reliability, etc.).
*/
typedef struct linkquality{
    float quality;
	bool recent;
}linkquality;

#endif