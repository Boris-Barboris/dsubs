module dsubs_server.connection;

import std.algorithm;
import std.exception;
import std.concurrency;
import std.conv: to;
import std.socket;
import core.atomic;
import core.thread;

import dsubs_common.api;
import dsubs_common.event;
import dsubs_common.containers.array;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.simulator;
public import dsubs_server.player;


/// TCP connection to some peer
final class PlayerConnection
{
	private
	{
		Socket m_sock;
		Address m_remoteAddr;
		Tid m_readerThread;
		Tid m_writerThread;
		bool m_authorized = false;
		shared bool m_closed = false;
		string m_username, m_password;
		void delegate(ubyte[])[] m_handlers;
	}

	/// not null if connection is authorized
	PlayerContext playerCtx;

	this(Socket sock)
	{
		m_sock = sock;
		sock.setKeepAlive(10, 10);
		m_remoteAddr = sock.remoteAddress();

		// fill handlers
		m_handlers.length = g_msgDemarshallers.length;
		m_handlers[ServerStatusReq.g_marshIdx] = &h_serverStatus;
		m_handlers[LoginReq.g_marshIdx] = &h_loginReq;
		m_handlers[EntityDbReq.g_marshIdx] = &h_entityDbReq;
		m_handlers[ClientPing.g_marshIdx] = &h_clientPing;
		m_handlers[SpawnReq.g_marshIdx] = &h_spawnReq;

		// std is not very nice with it's shared obsession,
		// we'll have to cast to it a lot
		m_readerThread = spawn(cast(shared void delegate()) &readProc);
		m_writerThread = spawn(cast(shared void delegate()) &writerProc);
	}

	/// send asynchroniously (writer thread will do it)
	void sendMessage(MsgT)(immutable(MsgT)* msgPtr)
	{
		send!(int, immutable(void)*)(
			m_writerThread, MsgT.g_marshIdx, cast(immutable(void)*) msgPtr);
	}

	/// send in caller thread (may block)
	void syncSendMessage(MsgT)(immutable(MsgT)* msgPtr)
	{
		auto msgBody = g_msgMarshallers[MsgT.g_marshIdx](msgPtr);
		sendBytes(msgBody);
	}

	/// if already closed\closing, does nothing. Otherwise, asynchroniously
	/// sends SessionClosed message, sleeps a little, closes the socket and
	/// unregisters the connection.
	void close(string reason = null)
	{
		if (!cas(&m_closed, false, true))
			return;
		info("Closing connection to ", m_remoteAddr, ", user: ", m_username);
		send!string(m_writerThread, reason);
	}

	/// synchronous version of close()
	void closeSync(string reason = null)
	{
		if (!cas(&m_closed, false, true))
			return;
		info("Closing connection to ", m_remoteAddr, ", user: ", m_username);
		send!bool(m_writerThread, true);
		doClose(reason);
	}

	@property string username() const { return m_username; }
	@property string password() const { return m_password; }
	@property bool closed() const { return m_closed; }

private:

	void doClose(string reason)
	{
		scope(exit) m_sock.close();
		if (reason.length > 0)
		{
			syncSendMessage(new immutable SessionClosedRes(reason));
			m_sock.shutdown(SocketShutdown.BOTH);
			Thread.sleep(msecs(100));
		}
		else
			m_sock.shutdown(SocketShutdown.BOTH);
		removeConnection(this);
		m_authorized = false;
	}

	int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce(received == 8, "Error during receive");
		enforce(header[0] >= 0 && header[0] < g_msgDemarshallers.length, "Unknown message");
		enforce(header[1] >= 0 && header[1] <= MAX_MSG_SIZE, "Message length invalid");
		trace("received header", header);
		return header;
	}

	ubyte[] recvBody(int size)
	{
		ubyte[] res = new ubyte[size];
		auto received = m_sock.receive(res);
		enforce(received == size, "Error during receive");
		return res;
	}

	void sendBytes(immutable(ubyte)[] msgBody)
	{
		auto sent = m_sock.send(msgBody);
		enforce(sent == msgBody.length, "Error during send");
	}

	void readProc()
	{
		try
		{
			while (true)
			{
				int[2] header = recvHeader();
				void delegate(ubyte[]) handler = m_handlers[header[0]];
				if (handler)
				{
					ubyte[] msgBody = recvBody(header[1]);
					handler(msgBody);
				}
				else
					throw new Exception("Unacceptable message header");
			}
		}
		catch (Exception e)
		{
			trace("Exception in reader: ", e.toString());
			close(e.msg);
		}
	}

	void writerProc()
	{
		try
		{
			bool closeServed = false;
			while (!closeServed)
			{
				receive(
					(int msgId, immutable(void)* msgPtr)
					{
						auto msgBody = g_msgMarshallers[msgId](msgPtr);
						sendBytes(msgBody);
					},
					(string reason)
					{
						closeServed = true;
						doClose(reason);
					},
					(bool dummy)
					{
						closeServed = true;
					}
				);
			}
		}
		catch (Exception e)
		{
			error("TCP writer thread throwed: ", e.toString());
			doClose(e.msg);
		}
	}


	//
	//	handlers
	//

	void h_serverStatus(ubyte[] msgBody)
	{
		ServerStatusReq msg;
		demarshalMessage(&msg, msgBody);
		int playersOnline = getPlayerCount();
		trace("g_authorizedConnections.length: ", playersOnline);
		immutable ServerStatusRes res = ServerStatusRes(API_VERSION, playersOnline);
		trace("Responding with ", res);
		sendBytes(marshalMessage(&res));
	}

	void h_clientPing(ubyte[] msgBody)
	{
		ClientPing msg;
		demarshalMessage(&msg, msgBody);
		trace("ping for ", m_username);
		immutable ServerPong res = ServerPong(msg.clientTime);
		sendBytes(marshalMessage(&res));
	}

	void h_loginReq(ubyte[] msgBody)
	{
		if (m_authorized)
			throw new Exception("Cannot authorize twice");
		LoginReq msg;
		demarshalMessage(&msg, msgBody);
		if (msg.username.length < 1)
		{
			immutable LoginRes res = LoginRes(false, "Enter nonempty username");
			trace("Responding with ", res);
			sendBytes(marshalMessage(&res));
			return;
		}
		m_username = msg.username;
		m_password = msg.password;
		trace("Authorizing as: ", m_username);
		if (confirmConnection(this))
		{
			m_authorized = true;
			Submarine sub = playerCtx.submarine;
			bool alreadySpawned = sub !is null;
			immutable LoginRes res = LoginRes(true, "Welcome to dsubs server",
				g_commonEntityDbHash, alreadySpawned);
			sendBytes(marshalMessage(&res));
			if (alreadySpawned)
			{
				immutable ReconnectStateRes rcres = ReconnectStateRes(
					sub.prototypeName,
					sub.propulsor.prototypeName);
				trace("User already spawned, sending reconnect state: ", rcres);
				sendBytes(marshalMessage(&rcres));
			}
		}
		else
		{
			immutable LoginRes res = LoginRes(false, "Invalid password");
			trace("Responding with ", res);
			sendBytes(marshalMessage(&res));
		}
	}

	void h_entityDbReq(ubyte[] msgBody)
	{
		enforce(m_authorized, "Permission denied");
		info("Entity database requested by ", m_username);
		sendBytes(g_marshalledCommonEntityDb);
	}

	void h_spawnReq(ubyte[] msgBody)
	{
		enforce(m_authorized, "Permission denied");
		enforce(playerCtx.submarine is null, "Player already has a submarine spawned");
		SpawnReq req;
		demarshalMessage(&req, msgBody);
		trace(req);

		// try to build a submarine
		Submarine sub = buildSubFromLoadout(req, playerCtx);
		randomizePosition(sub);

		// send response
		immutable SpawnRes res = SpawnRes(true, -1);
		sendBytes(marshalMessage(&res));

		synchronized(g_simMut.reader)
		{
			// finalize submarine and register it in a simulator
			info("Bootstrapping new submarine for ", username, req);
			sub.bootstrap();
			playerCtx.submarine = sub;
		}
	}
}