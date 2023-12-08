#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    moteids=[]
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3
    CMD_ROUTE = 10
    CMD_CONNECT = 11
    CMD_DISCONNECT = 12
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_HOST = 13
    CMD_HELLO = 14
    CMD_GOODBYE = 15
    CMD_WHISPER = 16
    CMD_CHAT = 17
    CMD_PRINT_USERS = 18
    CMD_FLOOD = 31
    
    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command"
    GENERAL_CHANNEL="general"
    HANDLER_CHANNEL="handler"

    # Project 1
    NEIGHBOR_CHANNEL="neighbor"
    FLOODING_CHANNEL="flooding"

    # Project 2
    ROUTING_CHANNEL="routing"
    LSP_CHANNEL="lsps"
    # Project 3
    TRANSPORT_CHANNEL="transport"
    TESTCONNECTION_CHANNEL = "testconnection"

    #Project 4
    CHAOS_SERVER_CHANNEL = "chaosServer"
    CHAOS_CLIENT_CHANNEL = "chaosClient"
    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap"

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo: ' + topoFile
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline())
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                # print " ", s[0], " ", s[1], " ", s[2]
                self.r.add(int(s[0]), int(s[1]), float(s[2]))
                if not int(s[0]) in self.moteids:
                    self.moteids=self.moteids+[int(s[0])]
                if not int(s[1]) in self.moteids:
                    self.moteids=self.moteids+[int(s[1])]

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in self.moteids:
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in self.moteids:
            # print "Creating noise model for ",i
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return
        self.t.getNode(nodeID).bootAtTime(1333*nodeID)

    def bootAll(self):
        i=0
        for i in self.moteids:
            self.bootNode(i)

    def moteOff(self, nodeID):
        print "Turning off",nodeID
        self.t.getNode(nodeID).turnOff()

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn()

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest)
        self.msg.set_id(ID)
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg))
    
    def route(self, source, dest, msg):
        self.sendCMD(self.CMD_ROUTE, source, "{0}{1}".format(chr(dest),msg))
    
    def connect(self, source, dest):
        self.sendCMD(self.CMD_CONNECT, source, "{0}{1}".format(chr(dest),""))
    
    def disconnect(self, source, dest):
        self.sendCMD(self.CMD_DISCONNECT, source, "{0}{1}".format(chr(dest),""))

    def host(self, server):
        self.sendCMD(self.CMD_HOST, server, "")

    def printUsers(self, client, server):
        self.sendCMD(self.CMD_PRINT_USERS, client, "{0}".format(chr(server)))

    def hello(self, source, dest, username):
        self.sendCMD(self.CMD_HELLO, source, "{0}{1}{2}".format(chr(dest),chr(len(username)),username))

    def goodbye(self, source, dest):
        self.sendCMD(self.CMD_GOODBYE, source, "{0}".format(chr(dest)))

    def whisper(self, source, dest, user, msg):
        self.sendCMD(self.CMD_WHISPER, source, "{0}{1}{2}{3}".format(chr(dest),chr(len(user)),chr(len(msg)),user+msg))

    def chat(self, source, msg):
        self.sendCMD(self.CMD_CHAT, source, "{0}{1}".format(chr(len(msg)), msg))

    def testServer(self, source, port, byteNum):
        self.sendCMD(self.CMD_TEST_SERVER, source, "{0}{1}".format(chr(port), chr(byteNum)))

    def testClient(self, source, srcPort, dest, destPort, byteNum):
        self.sendCMD(self.CMD_TEST_CLIENT, source, "{0}{1}{2}{3}".format(chr(srcPort),chr(dest),chr(destPort),chr(byteNum)))

    def flood(self,source,msg):
        self.sendCMD(self.CMD_FLOOD,source,"{0}{1}".format(chr(source),msg))
    
    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command")

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command")

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName
        self.t.addChannel(channelName, out)
    
    def removeChannel(self, channelName, out=sys.stdout):
        print 'Removing Channel', channelName
        

def main():
    s = TestSim()
    s.runTime(1)
    # s.loadTopo("long_line.topo")
    # s.loadTopo("smalltopo.topo")
    # s.loadTopo("tiny.topo")
    # s.loadTopo("example.topo")
    # s.loadTopo("circle.topo")
    s.loadTopo("tuna-melt.topo")
    # s.loadTopo("covid.topo")
    # s.loadTopo("dense.topo")
    # s.loadTopo("pizza.topo")
    # s.loadTopo("star.topo")

    # s.loadNoise("no_noise.txt")
    # s.loadNoise("some_noise.txt")
    s.loadNoise("meyer-heavy.txt")
    
    # s.addChannel(s.GENERAL_CHANNEL)
    # s.addChannel(s.NEIGHBOR_CHANNEL)
    # s.addChannel(s.FLOODING_CHANNEL)
    # s.addChannel(s.ROUTING_CHANNEL)                                                
    # s.addChannel(s.LSP_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)
    
    s.bootAll()
    
    # '''=== TINYCONTROLLER SIM ==='''
    s.runTime(256)

    # s.connect(1,2)

    # s.runTime(64)

    # s.connect(2,9)

    # s.runTime(64)

    # s.disconnect(1,2)

    # s.runTime(64)


    '''=== DEBUGGING SIM ==='''
    # x=9
    # y=23
    # print "\n================================================\n                ROUTING:", x ,"-->",y,"               \n================================================\n" 
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(x,y,"x->y")
    # s.runTime(1)
    # s.route(y,x,"y->x")
    # s.runTime(64)
    
    # print "\n================================================\n                ROUTING:",x,"--> 1                \n================================================\n"
    # s.route(x,1,"x->1")
    # s.runTime(64)


    # print("\n================================================\n                ROUTING: 1 --> 7                \n================================================\n")
    # s.route(1,7,"1->7")
    # s.runTime(10)
    
    # print("\n================================================\n                ROUTING: 7 --> 1                \n================================================\n")
    # s.route(7,1,"7->1")
    # s.runTime(10)
    
    # print("\n================================================\n                ROUTING: 9 --> 1                \n================================================\n")
    # s.route(9,1,"Hi 1!")
    # s.runTime(10)
    
    # print("\n================================================\n                DISABLING NODE 5                \n================================================\n")
    # s.moteOff(5)
    # s.runTime(10)
    
    # print("\n================================================\n                ROUTING: 1 --> 9                \n================================================\n")
    # s.route(1,9,"Hello 9!")
    # s.runTime(10)
    
    # print("\n================================================\n                DISABLING NODE 8                \n================================================\n")
    # s.moteOff(8)
    # s.runTime(10)
    
    # print("\n================================================\n                ROUTING: 1 --> 7                \n================================================\n")
    # s.route(1,7,"Still there 7?")
    # s.runTime(4)
if __name__ == '__main__':
    main()
