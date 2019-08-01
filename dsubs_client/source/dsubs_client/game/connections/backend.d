module dsubs_client.game.connections.backend;

import std.socket;
import std.process;

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
				if (Game.shuttingDown)
					return;
				synchronized(Game.mainMutex)
					Game.activeState.handleBackendDisconnect();
			};
		mixinHandlers(this);
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
		Game.cic.handleReconnectStateRes(res);
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

	void h_acousticStreamRes(AcousticStreamRes res)
	{
		Game.cic.handleAcousticStreamRes(res);
	}

	void h_sonarStreamRes(SonarStreamRes res)
	{
		Game.cic.handleSonarStreamRes(res);
	}

	void h_deathRes(DeathRes res)
	{
		Game.cic.handleDeathRes(res);
	}

	void h_tubeStateUpdateRes(TubeStateUpdateRes res)
	{
		Game.cic.handleTubeStateUpdateRes(res);
	}

	void h_ammoRoomStateUpdateRes(AmmoRoomStateUpdateRes res)
	{
		Game.cic.handleAmmoRoomStateUpdateRes(res);
	}
}


/// Worker thread that maintains connection to the backend open.
final class BackendConMaintainer
{
	private Thread m_thread;
	private shared bool exit_flag;
	private bool m_started;
	private BackendConnection m_con;

	@property BackendConnection con() { return m_con; }

	void start()
	{
		assert(!m_started);
		trace("starting BackendConMaintainer");
		assert(m_con is null);
		exit_flag = false;
		m_thread = new Thread(&proc);
		m_thread.start();
		m_started = true;
	}

	void stop()
	{
		trace("stopping BackendConMaintainer");
		atomicStore(exit_flag, true);
		if (m_started && m_con)
			m_con.close();
	}

	private void proc()
	{
		scope(exit) m_con = null;
		while (!atomicLoad(exit_flag))
		{
			try
			{
				Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
				auto addr = new InternetAddress(
					environment.get("DSUBS_BACKEND_HOST", "127.0.0.1"), 17855);
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