#ifndef __CHANNELS_H__
#define __CHANNELS_H__

// These should really be const value, but the dbg command will spit out a ton
// of warnings.
char COMMAND_CHANNEL[]="command";
char GENERAL_CHANNEL[]="general";
char HANDLER_CHANNEL[]="handler";

// Project 1
char NEIGHBOR_CHANNEL[]="neighbor";
char FLOODING_CHANNEL[]="flooding";

// Project 2
char ROUTING_CHANNEL[]="routing";
char LSP_CHANNEL[]="lsps";
// Project 3
char TRANSPORT_CHANNEL[]="transport";
char TESTCONNECTION_CHANNEL[] = "testconnection";

//Project 4
char CHAOS_SERVER_CHANNEL[] = "chaosServer";
char CHAOS_CLIENT_CHANNEL[] = "chaosClient";
// Personal Debuggin Channels for some of the additional models implemented.
char HASHMAP_CHANNEL[]="hashmap";
#endif
