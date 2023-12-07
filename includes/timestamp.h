#ifndef TIMESTAMP_H
#define TIMESTAMP_H

typedef struct timestamp{
    uint32_t expiration;
    uint32_t id;
    uint8_t byte;
    uint8_t intent;
}timestamp;

#endif