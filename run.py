from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("tuna-melt.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("meyer-heavy.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    # s.addChannel(s.TRANSPORT_CHANNEL)
    s.addChannel(s.TESTCONNECTION_CHANNEL)

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(100)

    # Set up a client/server connection demo.
    testServer = 1
    testServerPort = 10
    testClient = 4
    testClientPort = 12
    
    byteNumber = input("Enter a byte number:")

    s.testServer(testServer, testServerPort, byteNumber)
    s.runTime(50)

    s.testClient(testClient, testClientPort, testServer, testServerPort, byteNumber)
    s.runTime(50)

    s.runTime(100)

if __name__ == '__main__':
    main()