#ifndef TCPACK_H
#define TCPACK_H

#include "packet.h"
#include "wspack.h"

enum{
	tc_header_len = 7,
	tc_pkt_len = ws_max_pld_len,
	tc_max_pld_len = tc_pkt_len - tc_header_len //14
};

typedef nx_struct tcpack{
    nx_uint8_t flagsandsize;//left 3 bits sync,ack,fin, 5 bits for size of payload (max is 12, so extra bit)
    nx_uint8_t ports;//4 bits each, src|dest
    nx_uint8_t src;
    nx_uint8_t dest;
    nx_uint8_t currbyte;//first byte of payload's index in bytestream, [0,BUFFER_SIZE)
    nx_uint8_t nextbyte;//index of next expected byte in bytestram from counterpart, [0,BUFFER_SIZE)
    nx_uint8_t adWindow;//bytes
    nx_uint8_t data[tc_max_pld_len];
}tcpack;

// logNDPack(...): Prints the parameters of a given ndpack to a given channel.
void logTCpack(tcpack* input, char channel[]){
	dbg(channel, "INFO (tcPack): SYNC: %d | ACK: %d | FIN: %d | size: %d | cByte: %d | nByte: %d | DPort: %d | SPort: %d | Dest: %d | Src: %d | Window: %d\n",
	(input->flagsandsize&128)/128,
    (input->flagsandsize&64)/64,
    (input->flagsandsize&32)/32,
    (input->flagsandsize&31),
    input->currbyte,
    input->nextbyte,
    (input->ports&240)>>4, //240 = 11110000
    (input->ports&15), //15 = 00001111
    input->dest,
    input->src,
    input->adWindow
    );
}

#endif
