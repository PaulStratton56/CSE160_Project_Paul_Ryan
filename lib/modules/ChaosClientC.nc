configuration ChaosClientC{
    provides interface ChaosClient;
}

implementation{
   components ChaosClientP;
   ChaosClient = ChaosClientP.ChaosClient;

   components TinyControllerC as TC;
   ChaosClientP.TC -> TC;

   
}