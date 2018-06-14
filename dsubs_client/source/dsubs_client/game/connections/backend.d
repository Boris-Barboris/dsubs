module dsubs_client.game.connections.backend;

import std.socket;

import core.sync.mutex;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;

import dsubs_client.common;



/// TCP connection to backend dsubs server
final class BackendConnection: ProtocolConnection!BackendProtocol
{
	private Mutex m_mutex;

	/// Create the connection object and spool up worker threads.
	/// 'lockToHold' is a mutex guarding event objects.
	this(Socket sock, Mutex lockToHold)
	{
		assert(lockToHold);
		m_mutex = lockToHold;
		super(sock);
	}

	// clear all handlers from events
	void clearHandlers()
	{
		onConnectionClosed.clear();
		onConnectionSuccess.clear();
		onLoginRes.clear();
		onEntityDbRecieved.clear();
		onSpawnRes.clear();
		onSubKinematicRes.clear();
		onReconnectStateRes.clear();
	}

	// Subscribe to these events. They are all fired while holding m_mutex.
	Event!(void delegate(string reason)) onConnectionClosed;
	Event!(void delegate(ServerStatusRes res)) onConnectionSuccess;
	Event!(void delegate(LoginRes res)) onLoginRes;
	Event!(void delegate(EntityDbRes res)) onEntityDbRecieved;
	Event!(void delegate(SpawnRes res)) onSpawnRes;
	Event!(void delegate(SubKinematicRes res)) onSubKinematicRes;
	Event!(void delegate(ReconnectStateRes res)) onReconnectStateRes;
}