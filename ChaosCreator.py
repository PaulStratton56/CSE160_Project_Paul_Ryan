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
    s.addChannel(s.CHAOS_SERVER_CHANNEL)
    # s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)
    # s.addChannel(s.TESTCONNECTION_CHANNEL)

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(100)

    s.host(1)
    s.runTime(80)
    # s.printUsers(2,1)
    # s.runTime(10)
    s.hello(2,1, "Icywind")
    s.runTime(80)
    s.hello(3,1, "Gandle")
    s.runTime(80)
    # s.whisper(2,3,"Gandle","Testing123")
    # s.runTime(10)
    s.chat(3,"Hello_World")
    s.runTime(80)
    s.goodbye(2,1)
    s.runTime(80)
    s.goodbye(3,1)
    s.runTime(80)

if __name__ == '__main__':
    main()