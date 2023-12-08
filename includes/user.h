#ifndef USER_H
#define USER_H

enum{
    MAX_USERNAME_LENGTH = 16,//measured in 4 byte words so 64
    NULL_INSTRUCTION = 7,
    HELLO_INSTRUCTION = 0,
    CHAT_INSTRUCTION = 1,
    WHISPER_INSTRUCTION = 2,
    GOODBYE_INSTRUCTION = 3,
    LIST_USERS_INSTRUCTION = 4,
};

typedef struct user{
    uint8_t usernameLength;
    uint8_t username[4*MAX_USERNAME_LENGTH];
    uint8_t lastInstruction;
    uint8_t whisperSocketID;
    uint8_t bytesLeft;
}user;


#endif