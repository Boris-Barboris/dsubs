module dsubs_client.game.connections.cicserver;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
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
	}

	private
	{
		string m_expectedPw;
		CICServer m_cicserv;
	}

	mixin Readonly!(bool, "authorized");

private:

	void h_loginReq(CICLoginReq req)
	{
		enforce(req.password == m_expectedPw, "Wrong password");
		sendMessage(immutable CICLoginRes());
		m_authorized = true;
	}
}