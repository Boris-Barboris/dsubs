module dsubs_client.game.connections.backend;

import std.socket;

import core.atomic;
import core.thread;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;
import dsubs_common.network.connection;

import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.game.entities;



/// TCP connection to backend dsubs server
final class BackendConnection: ProtocolConnection!BackendProtocol
{
	this(Socket sock)
	{
		super(sock);
		onClose += (con)
			{
				synchronized(Game.mainMutex)
					Game.activeState.handleBackendDisconnect();
			};
		setHandler(&h_serverStatus);
		setHandler(&h_login);
		setHandler(&h_entityDb);
		setHandler(&h_reconnectState);
		setHandler(&h_spawnRes);
		setHandler(&h_subKinematicRes);
	}

private:

	void h_serverStatus(ServerStatusRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.mainMenuState.handleServerStatus(res);
		}
	}

	void h_login(LoginRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.mainMenuState.handleLogin(res);
		}
	}

	void h_entityDb(EntityDbRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.mainMenuState.handleEntityDb(res);
		}
	}

	void h_reconnectState(ReconnectStateRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.cic.handleReconnectStateRes(res);
		}
	}

	void h_spawnRes(SpawnRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.loadoutState.handleSpawnRes(res);
		}
	}

	void h_subKinematicRes(SubKinematicRes res)
	{
		Game.cic.handleSubKinematicRes(res);
	}
}


/// Worker thread that maintains connection to the backend open.
final class BackendConMaintainer
{
	private Thread m_thread;
	private shared bool exit_flag;
	private BackendConnection m_con;

	@property BackendConnection con() { return m_con; }

	void start()
	{
		assert(m_con is null);
		m_thread = new Thread(&proc);
		m_thread.start();
	}

	void stop()
	{
		atomicStore(exit_flag, true);
		if (m_con)
		{
			m_con.close();
			m_con = null;
		}
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
				m_con.sendMessage(immutable ServerStatusReq());
				m_con.join();
			}
			catch (Exception ex)
			{
				error(ex.msg);
				// flood protection
				Thread.sleep(seconds(10));
			}
		}
	}
}