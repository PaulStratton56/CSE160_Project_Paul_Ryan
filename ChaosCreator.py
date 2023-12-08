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

    if input("Launch interactive simulator? (1:Y \ 0:N)") == 1:
        userInput = 0
        while(userInput != -1):
            userInput = input("Chat: 1 | Whisper: 2 | Goodbye: 3 | User Request: 4 | Hello: 5 | Quit: -1\nEnter command: ")
            if userInput == 1:
                client = input("Enter node to chat: ")
                message = input("Enter message: ")
                s.chat(client, message)
            if userInput == 2:
                client = input("Enter whisper sender: ")
                targetClient = input("Enter whisper recipient username: ")
                targetClientID = input("Enter whisper recipient ID: ")
                message = input("Enter message: ")
                s.whisper(client, targetClientID, targetClient, message)
            if userInput == 3:
                client = input("Enter quitting node: ")
                server = input("Enter server to quit from: ")
                s.goodbye(client, server)
            if userInput == 4:
                client = input("Enter client: ")
                server = input("Enter server: ")
                s.printUsers(client, server)
            if userInput == 5:
                client = input("Enter client: ")
                server = input("Enter server: ")
                username = input("Enter username: ")
                s.hello(client, server, username)
            s.runTime(30)
    else:
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