module dsubs_client.game.cic.server;

import dsubs_common.api.protocols.backend;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.cic.listener;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.state;
import dsubs_client.game.connections.backend;

public import dsubs_client.game.connections.cicclient;


/**
CIC stands for command information center. It is a broadcast and synchronization
server responsible for cooperative gameplay.
*/
final class CICServer
{
	private
	{
		CICListener m_listener;
		CICState m_state;
		BackendConnection m_bcon;
	}

	mixin Readonly!(int, "spawnId");

	this(string password, BackendConnection bcon, int spawnId = -1)
	{
		m_listener = new CICListener(this, password);
		m_state = new CICState();
		m_bcon = bcon;
		m_spawnId = spawnId;
	}

	void start()
	{
		assert(m_listener);
		m_listener.start();
		Game.window.title = "dsubs (coop port " ~ m_listener.port.to!string ~ ")";
	}

	@property CICListener listener() { return m_listener; }

	void stop()
	{
		info("shutting CIC server down");
		m_listener.stop();
	}

	@property CICState state() { return m_state; }

	void handleReconnectStateRes(ReconnectStateRes res)
	{
		synchronized(this)
		{
			m_state.handleReconnectStateRes(res);
			m_listener.broadcast(cast(immutable CICReconnectStateRes) res);
		}
	}

	void handleSubKinematicRes(SubKinematicRes res)
	{
		synchronized(this)
		{
			m_state.handleSubKinematicRes(res);
			m_listener.broadcast(cast(immutable CICSubKinematicRes) res);
		}
	}

	void handleCICThrottleReq(CICThrottleReq req)
	{
		synchronized
		{
			synchronized(this)
			{
				m_state.handleThrottleReq(req);
			}
			// broadcast here is outside of lock because the message is idempotent
			m_listener.broadcast(cast(immutable CICThrottleReq) req);
			m_bcon.sendMessage(cast(immutable ThrottleReq) req);
		}
	}

	void handleCICCourseReq(CICCourseReq req)
	{
		synchronized
		{
			synchronized(this)
			{
				m_state.handleCourseReq(req);
			}
			// broadcast here is outside of lock because the message is idempotent
			m_listener.broadcast(cast(immutable CICCourseReq) req);
			m_bcon.sendMessage(cast(immutable CourseReq) req);
		}
	}

	void handleCICListenDirReq(CICListenDirReq req)
	{
		synchronized
		{
			synchronized(this)
			{
				m_state.handleListenDirReq(req);
			}
			// broadcast here is outside of lock because the message is idempotent
			m_listener.broadcast(cast(immutable CICListenDirReq) req);
			m_bcon.sendMessage(cast(immutable ListenDirReq) req);
		}
	}

	void handleAcousticStreamRes(AcousticStreamRes res)
	{
		CICSubAcousticRes bdcst;
		bdcst.data = res.data;
		bdcst.audio = res.audio;
		assert(m_state.recStateInitialized);
		assert(res.atTime == m_state.recState.subSnap.atTime);
		bdcst.rotationAtTime = m_state.recState.subSnap.rotation;
		m_listener.broadcast(cast(immutable CICSubAcousticRes) bdcst);
	}

	void handleSonarStreamRes(SonarStreamRes res)
	{
		CICSubSonarRes bdcst;
		bdcst.data = res.data;
		m_listener.broadcast(cast(immutable CICSubSonarRes) bdcst);
	}

	void handleCICEmitPingReq(CICEmitPingReq req)
	{
		m_bcon.sendMessage(cast(immutable EmitPingReq) req);
	}
}