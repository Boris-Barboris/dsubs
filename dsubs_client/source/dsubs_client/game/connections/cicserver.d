module dsubs_client.game.connections.cicserver;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;
import dsubs_common.network.connection;

import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.protocol;
import dsubs_client.game.cic.server;
import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;


/// TCP connection from CIC server to client.
final class CICServerConnection: ProtocolConnection!CICProtocol
{
	this(CICServer cicserv, Socket sock, string expectedPw)
	{
		assert(expectedPw.length <= 64);
		super(sock);
		m_expectedPw = expectedPw;
		m_cicserv = cicserv;
		mixinHandlers(this);
	}

	private
	{
		string m_expectedPw;
		CICServer m_cicserv;
	}

	mixin Readonly!(bool, "authorized");
	mixin Readonly!(bool, "inSimFlow");

private:

	void h_loginReq(CICLoginReq req)
	{
		enforce(!m_authorized, "already authorized");
		enforce(req.password == m_expectedPw, "Wrong password");
		info("CIC peer connection authorized");
		immutable(ubyte)[] dbHash;
		synchronized(Game.mainMutex)
		{
			dbHash = Game.entityDbHash;
		}
		sendMessage(immutable CICLoginRes(dbHash));
		m_authorized = true;
	}

	void h_entityDbReq(CICEntityDbReq req)
	{
		enforce(m_authorized, "unauthorized");
		EntityDbRes db;
		synchronized(Game.mainMutex)
		{
			db = Game.entityDb;
		}
		sendMessage(cast(immutable CICEntityDbRes) db);
	}

	void h_enterSimFlowReq(CICEnterSimFlowReq req)
	{
		enforce(m_authorized, "unauthorized");
		enforce(!m_inSimFlow, "already in simulator flow");
		synchronized(m_cicserv.state.ctcMut)
		{
			// required to wait on condition
			synchronized(m_cicserv.state.rsMut)
			{
				sendMessage(m_cicserv.state.awaitCicRecState());
				m_inSimFlow = true;
			}
			sendBytes(m_cicserv.state.serializeLastNData(100));
		}
	}

	void h_throttleReq(CICThrottleReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICThrottleReq(req);
	}

	void h_courseReq(CICCourseReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICCourseReq(req);
	}

	void h_listenDirReq(CICListenDirReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICListenDirReq(req);
	}

	void h_emitPingReq(CICEmitPingReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICEmitPingReq(req);
	}

	void h_createContactFromDataReq(CICCreateContactFromDataReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICCreateContactFromDataReq(req);
	}

	void h_contactUpdateReq(CICContactUpdateReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICContactUpdateReq(req);
	}

	void h_contactDataReq(CICContactDataReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICContactDataReq(req);
	}

	void h_dropContactReq(CICDropContactReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICDropContactReq(req);
	}

	void h_dropDataReq(CICDropDataReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICDropDataReq(req);
	}

	void h_contactMergeReq(CICContactMergeReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICContactMergeReq(req);
	}

	void h_createContactFromHTrackerReq(CICCreateContactFromHTrackerReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICCreateContactFromHTrackerReq(req);
	}

	void h_updateTrackerReq(CICUpdateTrackerReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICUpdateTrackerReq(req);
	}

	void h_dropTrackerReq(CICDropTrackerReq req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICDropTrackerReq(req);
	}

	void h_trimContactDataReq(CICTrimContactData req)
	{
		enforce(m_inSimFlow, "not in simulator flow");
		m_cicserv.handleCICTrimContactData(req);
	}
}