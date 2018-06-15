module dsubs_client.game.connections.backend;

import std.socket;

import core.atomic;
import core.thread;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;

import dsubs_client.common;



/// TCP connection to backend dsubs server
final class BackendConnection: ProtocolConnection!BackendProtocol
{
	/// Create the connection object and spool up worker threads.
	/// 'lockToHold' is a mutex guarding event objects.
	this(Socket sock)
	{
		super(sock);
	}
}


/// Worker thread that maintains connection to the backend open.
final class BackendConMaintainer
{
	private Thread m_thread;
	private shared bool exit_flag;
	private BackendConnection m_con;

	this()
	{
		m_thread = new Thread(&proc, 16 * 1024);
	}

	void start()
	{
		m_thread.start();
	}

	void stop()
	{
		atomicStore(exit_flag, true);
		BackendConnection c = m_con;
		if (c)
			c.close();
		m_con = null;
	}

	private void proc()
	{
		while (!atomicLoad(exit_flag))
		{
			try
			{
				Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
				auto addr = new InternetAddress("127.0.0.1", 17855);
				info("Attempting to connect to backend ", addr);
				clientSock.connect(addr);
				m_con = new BackendConnection(clientSock);
				m_con.start();
				m_con.join();
			}
			catch (Exception ex)
			{
				error(ex.toString());
				Thread.sleep(seconds(3));
			}
		}
	}
}