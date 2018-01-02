module dsubs_server.app;

import std.socket;

import dsubs_common.api;

import dsubs_server.common;
import dsubs_server.connection;


int main(string[] argv)
{
	version ( unittest ) info("Unit tests OK");
	Socket listenSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
	listenSock.bind(new InternetAddress(13337));
	listenSock.listen(16);
	Socket newSock = listenSock.accept();
	while (newSock)
	{
		info("Accepted connection from ", newSock.remoteAddress());
		addNewConnection(new PlayerConnection(newSock));
		newSock = listenSock.accept();
	}
	return 0;
}