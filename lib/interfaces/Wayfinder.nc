interface Wayfinder{
    command uint8_t getRoute(uint8_t dest);
    command void onBoot();
    command void printTopo();
    command void printRoutingTable();
    command uint16_t getMissing();
}