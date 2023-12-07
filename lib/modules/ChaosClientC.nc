configuration ChaosClientC{
    provides interface ChaosClient;
}

implementation{
   components ChaosClientP;
   ChaosClient = ChaosClientP.ChaosClient;
}