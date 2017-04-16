module dsubs_server.front.server;

import core.time;

import vibe.core.core: runTask, sleep;
import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;

/// API frontend
class DsubsTCPServer
{
	private string address;
	private ushort port;

	this(string address, ushort port)
	{
		this.address = address;
		this.port = port;
	}

	TCPListener listener;

	void start()
	{
		//TCPListenOptions opts = TCPListenOptions.distribute;
		listener = listenTCP(port, &tcp_callback, address);//, opts);
	}

	void stop()
	{
		listener.stopListening();
	}

	void tcp_callback(TCPConnection con)
	{
		logInfo("Established connection from " ~ con.peerAddress);
		while (true && con.connected)
		{
			bool ready = con.waitForData();	// dur!"msecs"(500)
			if (ready)
			{
				logInfo("Stream ready to be read");
			    string text = con.readAllUTF8();
				logInfo("Got tcp frame with content " ~ text);
			}
		}
	}
}



unittest
{
	auto server = new DsubsTCPServer("0.0.0.0", 19320);
	server.start();	
	scope(exit) server.stop();
	auto client = connectTCP("127.0.0.1", 19320);
	scope(exit) client.close();
	client.write("123");
	client.flush();
	assert(client.waitForData());
	string result = client.readAllUTF8();
	assert(result == "Hello");
}