interface Wayfinder{
    command uint16_t getRoute(uint16_t dest);
    command void onBoot();
    command void printTopo();
}