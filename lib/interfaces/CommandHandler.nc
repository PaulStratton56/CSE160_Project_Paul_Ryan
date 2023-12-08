interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void flood(uint8_t* payload);
   event void route(uint8_t dest, uint8_t* payload);
   event void connect(uint8_t dest);
   event void disconnect(uint8_t dest);
   event void host();
   event void printUsers(uint8_t dest);
   event void hello(uint8_t dest, uint8_t* username, uint8_t userLength);
   event void goodbye(uint8_t dest);
   event void whisper(uint8_t dest, uint8_t msgLen, uint8_t* payload, uint8_t userLen);
   event void chat(uint8_t* payload, uint8_t msgLen);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port, uint8_t bytes);
   event void setTestClient(uint8_t srcPort, uint8_t dest, uint8_t destPort, uint8_t bytes);
   event void setAppServer();
   event void setAppClient();
}
