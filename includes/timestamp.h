#ifndef TIMESTAMP_H
#define TIMESTAMP_H

typedef struct timestamp{
    uint32_t expiration;
    uint32_t id;
	uint16_t seq;
    uint8_t byte;
}timestamp;

#endif