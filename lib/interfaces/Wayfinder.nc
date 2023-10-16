interface Wayfinder{
    command uint8_t getRoute(uint8_t dest);
    command void onBoot();
    command void printTopo();
}