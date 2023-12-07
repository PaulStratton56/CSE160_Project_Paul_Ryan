configuration ChaosServerC{
    provides interface ChaosServer;
}

implementation{
   components ChaosServerP;
   ChaosServer = ChaosServerP.ChaosServer;
}