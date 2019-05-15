module dsubs_client.game.cic.server;

import dsubs_common.api.protocols.backend;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.cic.listener;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.state;
import dsubs_client.game.cic.tracking;
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
		WaterfallAnalyzer[] m_wfAnalizers;
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
		const SubmarineTemplate sbmTpl = *Game.entityManager.
			submarineTemplates[res.submarineName];
		foreach (size_t i, const HydrophoneTemplate ht; sbmTpl.hydrophones)
			m_wfAnalizers ~= new WaterfallAnalyzer(ht, i.to!int);
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
		KinematicSnapshot snap;
		synchronized(m_state.rsMut)
		{
			snap = m_state.recState.subSnap;
		}
		// waterfall analyzers
		synchronized(m_state.ctcMut)
		{
			foreach (HydrophoneData hd; res.data)
			{
				WaterfallAnalyzer al = m_wfAnalizers[hd.hydrophoneIdx];
				al.processNewData(hd.antennaes, snap);
				CICWaterfallUpdateRes wfu;
				wfu.hydrophoneIdx = hd.hydrophoneIdx;
				wfu.peaks = al.getPeaks();
				wfu.trackers = al.getTrackers();
				m_listener.broadcast(cast(immutable) wfu);
				ContactData[] newCdata = al.generateRayData();
				foreach (cd; newCdata)
					processContactData(cd);
			}
		}
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

	/*
	Contact management.
	*/

	void handleCICCreateContactFromDataReq(CICCreateContactFromDataReq req)
	{
		enforce(req.initialData.id < 0, "ContactData mus be new sample");
		enforce(req.initialData.type != DataType.Speed,
			"Cannot create contact from speed data");
		CICContactCreatedFromDataRes res;
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

	void handleCICCreateContactFromHTrackerReq(CICCreateContactFromHTrackerReq req)
	{
		enforce(req.hydrophoneIdx >= 0 && req.hydrophoneIdx < m_wfAnalizers.length);
		CICContactCreatedFromHTrackerRes res;
		synchronized (m_state.ctcMut)
		{
			Contact* ctc = m_state.createContact(req.ctcIdPrefix);
			res.newContact = *ctc;
			TrackerId tid = TrackerId(req.hydrophoneIdx, ctc.id);
			res.tracker = m_wfAnalizers[req.hydrophoneIdx].createTracker(tid, req.bearing);
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

	private void processContactData(ContactData cd)
	{
		ContactData* data = m_state.updateOrCreateData(cd);
		if (data !is null)
		{
			CICContactDataReq res = CICContactDataReq(*data);
			m_listener.broadcast(cast(immutable) res);
			Contact* updatedContact = m_state.updateSolutionFromNewData(data);
			if (updatedContact)
				m_listener.broadcast(immutable CICContactUpdateReq(*updatedContact));
		}
		// we do not throw here because contact could be deleted right after the
		// message was sent
	}

	void handleCICContactDataReq(CICContactDataReq req)
	{
		synchronized (m_state.ctcMut)
		{
			processContactData(req.data);
		}
	}

	void handleCICDropContactReq(CICDropContactReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_state.dropContact(req.ctcId))
			{
				foreach (WaterfallAnalyzer wa; m_wfAnalizers)
					wa.dropTracker(req.ctcId);
				m_listener.broadcast(cast(immutable) req);
			}
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
		enforce(req.sourceCtcId != req.destCtcId, "cannot merge into itself");
		synchronized(m_state.ctcMut)
		{
			if (m_state.mergeContacts(req.sourceCtcId, req.destCtcId))
			{
				foreach (WaterfallAnalyzer wa; m_wfAnalizers)
					wa.mergeTrackers(req.sourceCtcId, req.destCtcId);
				m_listener.broadcast(cast(immutable) req);
				// destination contact is often updated
				m_listener.broadcast(immutable CICContactUpdateReq(
					m_state.getContact(req.destCtcId)));
			}
		}
	}

	void handleCICUpdateTrackerReq(CICUpdateTrackerReq req)
	{
		enforce(req.tracker.id.sensorIdx >= 0 &&
			req.tracker.id.sensorIdx < m_wfAnalizers.length);
		synchronized (m_state.ctcMut)
		{
			HydrophoneTracker newState;
			if (m_wfAnalizers[req.tracker.id.sensorIdx].updateTracker(
				req.tracker.id.ctcId, req.tracker.bearing, newState))
			{
				m_listener.broadcast(immutable CICUpdateTrackerReq(newState));
			}
		}
	}

	void handleCICDropTrackerReq(CICDropTrackerReq req)
	{
		enforce(req.tid.sensorIdx >= 0 && req.tid.sensorIdx < m_wfAnalizers.length);
		synchronized (m_state.ctcMut)
		{
			if (m_wfAnalizers[req.tid.sensorIdx].dropTracker(req.tid.ctcId))
			{
				m_listener.broadcast(req);
			}
		}
	}

	void handleCICTrimContactData(CICTrimContactData req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_state.trimData(req.ctcId, req.olderThan))
				m_listener.broadcast(req);
		}
	}
}