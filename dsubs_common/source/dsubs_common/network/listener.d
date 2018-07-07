module dsubs_common.network.listener;

import std.socket;

import dsubs_common.utils;


struct TcpServer
{
	string listenAddr;
	ushort port;
	// TODO: encryption and cert stuff
}

/// Create TCP listener socket
Socket listenTcp(TcpServer settings)
{
	Address addr = parseAddress(settings.listenAddr, settings.port);
	Socket listenSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
	scope(failure) listenSock.close();
	listenSock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	version (Windows) { /* windows has socket buf size autotuning */ }
	else
	{
		listenSock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVBUF, 64 * 1024);
		listenSock.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDBUF, 256 * 1024);
	}
	listenSock.bind(addr);
	listenSock.listen(16);
	info("Serving TCP on ", addr);
	return listenSock;
}

/// Serve Tcp connection requests in caller thread. To abort the infinite loop, close
/// the listenSocket.
void serveTcp(Socket listenSock, scope void delegate(Socket) onAccept)
{
	scope(exit) listenSock.close();
	while (true)
	{
		Socket s = listenSock.accept();
		info("TCP peer connected from ", s.remoteAddress.toAddrString());
		onAccept(s);
	}
}