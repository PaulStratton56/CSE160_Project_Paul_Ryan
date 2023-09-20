configuration PacketHandlerC{
    provides interface PacketHandler;
}

implementation{
    components PacketHandlerP;
    PacketHandler = PacketHandlerP.PacketHandler;

    components NeighborDiscoveryC as Neighbor;
    PacketHandlerP.Neighbor -> Neighbor;

}