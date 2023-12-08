from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("tuna-melt.topo")
    # s.loadNoise("meyer-heavy.txt")
    s.loadNoise("no_noise.txt")
    s.bootAll()

    # s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.CHAOS_SERVER_CHANNEL)
    s.addChannel(s.CHAOS_CLIENT_CHANNEL)
    # s.addChannel(s.GENERAL_CHANNEL)
    # s.addChannel(s.TRANSPORT_CHANNEL) 
    # s.addChannel(s.TESTCONNECTION_CHANNEL)

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(100)

    s.host(1)
    s.runTime(20)
    # s.printUsers(2,1)
    # s.runTime(10)
    s.hello(16,1, "Icywind")
    s.runTime(20)
    s.hello(23,1, "Gand")
    s.runTime(20)
    s.chat(23,"Hello World")
    s.runTime(20)
    
    s.hello(7,1, "Saur")
    s.runTime(20)
    
    s.chat(7,"Hi everyone")
    s.runTime(20)
    
    s.whisper(7,23,"Gand","Hi G!")
    s.runTime(20)
    
    s.printUsers(16,1)
    s.runTime(20)
    
    s.goodbye(16,1)
    s.runTime(20)
    s.goodbye(23,1)
    s.runTime(20)
    s.goodbye(7,1)
    s.runTime(20)

if __name__ == '__main__':
    main()