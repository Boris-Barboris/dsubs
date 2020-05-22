module dsubs_client.game.connections.backend;

import std.socket;
import std.process;
import std.datetime: Date;

import core.atomic;
import core.thread;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.messages;
import dsubs_common.api.marshalling;
import dsubs_common.network.connection;

import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.game.gamestate: GameState;
import dsubs_client.game.states.loadout: LoadoutState;
import dsubs_client.game.states.loginscreen: LoginScreenState;
import dsubs_client.game.states.replay: ReplayState;
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
			GameState activeState = Game.activeState;
			if (cast(LoginScreenState) activeState)
				Game.loginScreenState.handleServerStatus(res);
		}
	}

	void h_replayDataRes(ReplayDataRes res)
	{
		Date date = Date.fromISOExtString(res.metricsDate);
		synchronized(Game.mainMutex)
		{
			Game.activeState = new ReplayState(date, res.replaySlices);
		}
	}

	void h_loginSuccess(LoginSuccessRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.loginScreenState.handleLoginSuccess(res);
		}
	}

	void h_loginFailure(LoginFailureRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.loginScreenState.handleLoginFailure(res);
		}
	}

	void h_entityDb(EntityDbRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.loginScreenState.handleEntityDb(res);
		}
	}

	void h_reconnectState(ReconnectStateRes res)
	{
		synchronized(Game.mainMutex)
		{
			LoadoutState.handleReconnectStateRes(res);
		}
	}

	void h_availableScenariosRes(AvailableScenariosRes res)
	{
	}

	void h_spawnFailureRes(SpawnFailureRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.loadoutState.handleSpawnFailureRes(res);
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

	void h_simFlowEndRes(SimFlowEndRes res)
	{
		Game.cic.handleSimFlowEndRes(res);
	}

	void h_tubeStateUpdateRes(TubeStateUpdateRes res)
	{
		Game.cic.handleTubeStateUpdateRes(res);
	}

	void h_ammoRoomStateUpdateRes(AmmoRoomStateUpdateRes res)
	{
		Game.cic.handleAmmoRoomStateUpdateRes(res);
	}

	void h_mapOverlayUpdateRes(MapOverlayUpdateRes res)
	{
		Game.cic.handleMapOverlayUpdateRes(res);
	}

	void h_chatMessageRes(ChatMessageRes res)
	{
		Game.cic.handleChatMessageRes(res);
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
				AddressInfo[] addrs;
				version (prod)
				{
					addrs = getAddressInfo(
						environment.get("DSUBS_BACKEND_HOST", "borisbarboris.duckdns.org"),
						environment.get("DSUBS_BACKEND_PORT", "17955"));
				}
				else
				{
					addrs = getAddressInfo(
						environment.get("DSUBS_BACKEND_HOST", "127.0.0.1"),
						environment.get("DSUBS_BACKEND_PORT", "17855"));
				}
				if (addrs.length < 1)
					throw new Exception("no backend address could be resolved");
				info("Attempting to connect to backend ", addrs[0]);
				clientSock.connect(addrs[0].address);
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