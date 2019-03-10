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
	@property CICState state() { return m_state; }

	void stop()
	{
		info("shutting CIC server down");
		m_listener.stop();
	}

	void handleReconnectStateRes(ReconnectStateRes res)
	{
		enforce(!m_state.recStateInitialized,
			"protocol flow error: unexpected duplicate ReconnectStateRes");
		m_state.handleReconnectStateRes(res);
	}

	void handleSubKinematicRes(SubKinematicRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleSubKinematicRes(res);
		}
		m_listener.broadcast(cast(immutable CICSubKinematicRes) res);
	}

	void handleCICThrottleReq(CICThrottleReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				m_state.handleThrottleReq(req);
			}
			m_bcon.sendMessage(cast(immutable ThrottleReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICCourseReq(CICCourseReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				m_state.handleCourseReq(req);
			}
			m_bcon.sendMessage(cast(immutable CourseReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICListenDirReq(CICListenDirReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				m_state.handleListenDirReq(req);
			}
			m_bcon.sendMessage(cast(immutable ListenDirReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleAcousticStreamRes(AcousticStreamRes res)
	{
		CICSubAcousticRes bdcst;
		bdcst.data = res.data;
		bdcst.audio = res.audio;
		enforce(m_state.recStateInitialized);
		enforce(res.atTime == m_state.recState.subSnap.atTime);
		bdcst.rotationAtTime = m_state.recState.subSnap.rotation;
		m_listener.broadcast(cast(immutable) bdcst);
	}

	void handleSonarStreamRes(SonarStreamRes res)
	{
		CICSubSonarRes bdcst;
		enforce(res.atTime == m_state.recState.subSnap.atTime);
		bdcst.data = res.data;
		m_listener.broadcast(cast(immutable) bdcst);
	}

	void handleCICEmitPingReq(CICEmitPingReq req)
	{
		m_bcon.sendMessage(cast(immutable EmitPingReq) req);
	}

	// contac management

	void handleCICCreateContactFromDataReq(CICCreateContactFromDataReq req)
	{
		enforce(req.initialData.id < 0, "ContactData mus be new sample");
		enforce(req.initialData.type != DataType.Speed,
			"Cannot create contact from speed data");
		CICContactCreatedRes res;
		synchronized (m_state.ctcMut)
		{
			Contact* ctc = m_state.createContact(req.ctcIdPrefix);
			req.initialData.ctcId = ctc.id;
			ContactData* data = m_state.updateOrCreateData(req.initialData);
			if (data is null)
				assert(0, "should not have happenned");
			m_state.initializeSolution(ctc, data);
			res.newContact = *ctc;
			res.initialData = *data;
			m_listener.broadcast(cast(immutable) res);
		}
	}

	void handleCICContactUpdateReq(CICContactUpdateReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_state.updateContact(req.contact))
				m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICContactDataReq(CICContactDataReq req)
	{
		synchronized (m_state.ctcMut)
		{
			ContactData* data = m_state.updateOrCreateData(req.data);
			if (data !is null)
			{
				CICContactDataReq res = CICContactDataReq(*data);
				m_listener.broadcast(cast(immutable) res);
			}
		}
	}

	void handleCICDropContactReq(CICDropContactReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_state.dropContact(req.ctcId))
				m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICDropDataReq(CICDropDataReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_state.dropData(req.dataId))
				m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICContactMergeReq(CICContactMergeReq req)
	{
		if (req.sourceCtcId == req.destCtcId)
			return;
		synchronized(m_state.ctcMut)
		{
			if (m_state.mergeContacts(req.sourceCtcId, req.destCtcId))
				m_listener.broadcast(cast(immutable) req);
		}
	}
}