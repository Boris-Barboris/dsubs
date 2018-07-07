module dsubs_client.game.cic.server;

import dsubs_common.api.protocols.backend;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.cic.listener;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.state;

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
	}

	mixin Readonly!(int, "spawnId");

	this(string password, int spawnId = -1)
	{
		m_listener = new CICListener(this, password);
		m_state = new CICState();
		m_spawnId = spawnId;
	}

	void start()
	{
		m_listener.start();
	}

	void stop()
	{
		if (m_listener)
		{
			info("shutting CIC server down");
			m_listener.stop();
			m_listener = null;
		}
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
		synchronized(this)
		{
			m_state.handleThrottleReq(req);
			m_listener.broadcast(cast(immutable CICThrottleReq) req);
			Game.bconm.con.sendMessage(cast(immutable ThrottleReq) req);
		}
	}

	void handleCICCourseReq(CICCourseReq req)
	{
		synchronized(this)
		{
			m_state.handleCourseReq(req);
			m_listener.broadcast(cast(immutable CICCourseReq) req);
			Game.bconm.con.sendMessage(cast(immutable CourseReq) req);
		}
	}
}