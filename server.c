­/* A simple server in the internet domain using TCP
   The port number is passed as an argument */
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

#include <sys/types.h> 
#include <sys/socket.h>
#include <netinet/in.h>

void error(char *msg)
{
    perror(msg);
­
}

int main(int argc, char *argv[])
{
     int sockfd, newsockfd, portno;
     unsigned int clilen;
     char buffer[256];
     struct sockaddr_in serv_addr, cli_addr;
     int n;

     // make sure we're invoked with a port number on the command line
     if (argc < 2) {
         fprintf(stderr,"ERROR, no port provided\n");
         exit(1);
     }

     // create the socket
     sockfd = socket(AF_INET, SOCK_STREAM, 0);
     if (sockfd < 0) 
        error("ERROR opening socket");

     // create a "struct sockaddr_in" to specify the server's IP, port, proto
     bzero((char *) &serv_addr, sizeof(serv_addr));
     portno = atoi(argv[1]);
     serv_addr.sin_family = AF_INET;
     serv_addr.sin_addr.s_addr = INADDR_ANY;
     serv_addr.sin_port = htons(portno);

     // bind the socket to the address in the "struct sockaddr_in"
     if (bind(sockfd, (struct sockaddr *) &serv_addr,
              sizeof(serv_addr)) < 0) 
              error("ERROR on binding");

     // tell the OS I'm willing to accept connections on the socket
     listen(sockfd,5);

     // wait for a connection to arrive from a client
     clilen = sizeof(cli_addr);
     newsockfd = accept(sockfd, 
                 (struct sockaddr *) &cli_addr, 
                 &clilen);
     if (newsockfd < 0) 
          error("ERROR on accept");

     // read some data from the client
     bzero(buffer,256);
     n = read(newsockfd,buffer,255);
     if (n < 0) error("ERROR reading from socket");

     // print out the message
     printf("Here is the message: '%s'\n",buffer);

     // write a response to the client
     n = write(newsockfd,"I got your message",18);
     if (n < 0) error("ERROR writing to socket");

     // close the socket  (optional; OS will do when process terminates)
     close(sockfd);
     return 0; 
}

