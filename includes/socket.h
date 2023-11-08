#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    CONNECTED,
    SYNC_SENT,
    SYNC_RCVD,
};

typedef uint8_t port_t;
typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint8_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    // uint8_t flag;
    enum socket_state state;
    socket_port_t srcPort;  
    socket_addr_t dest;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t nextToWrite; //Index of last written byte to sendbuff
    uint8_t lastAcked; //Index of the last Acked byte in the sendbuff
    uint8_t nextToSend; //Index of the last sent byte in sendbuff
    uint16_t seq;

    // This is the receiver portion
    uint8_t recvBuff[SOCKET_BUFFER_SIZE];
    uint8_t nextToRead; //Index of the last byte read from rcvdbuff
    uint8_t lastRecv; //Index of the last received byte in rcvdbuff
    uint8_t nextExpected; //Index of the next expected byte for rcvdbuff
    uint16_t seqToRecv;

    uint16_t RTT;
    uint8_t effectiveWindow;
}socket_store_t;

#endif
