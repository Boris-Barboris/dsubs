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
		setHandler(&h_loginReq);
		setHandler(&h_entityDbReq);
		setHandler(&h_enterSimFlowReq);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
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
		synchronized(m_cicserv)
		{
			if (m_cicserv.state.recStateInitialized)
				sendMessage(m_cicserv.state.recState);
			m_inSimFlow = true;
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
}