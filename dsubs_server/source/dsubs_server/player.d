module dsubs_server.player;

import core.sync.mutex;

import dsubs_common.containers.array;

import dsubs_server.common;
import dsubs_server.connection: PlayerConnection;


/// This structure hold player information. It is expected to always be
/// mutated by one thread only
final class PlayerContext
{
	this(string uname)
	{
		username = uname;
	}

	const string username;
	string password;
	bool isBot = false;
	int playerKillCount;
	int botKillCount;
	int deathCount;

	/// Instance of PlayerConnection class
	PlayerConnection connection;
}


private __gshared PlayerContext[string] g_players;
private shared Mutex g_playerMut;

shared static this()
{
	g_playerMut = new shared Mutex();
}

PlayerContext getOrCreatePlayerCtx(string username)
{
	synchronized (g_playerMut)
	{
		PlayerContext* ctx = username in g_players;
		if (ctx is null)
		{
			PlayerContext newCtx = new PlayerContext(username);
			g_players[username] = newCtx;
			return newCtx;
		}
		return *ctx;
	}
}

int getPlayerCount()
{
	return g_players.length;
}

private shared Mutex g_conMut;		/// mutex that guards connection containers
private __gshared
{
	PlayerConnection[] g_freshConnections;	/// all unauthorized connections
}

shared static this()
{
	g_conMut = new shared Mutex();
}

/// add new connection to g_greshConnections array
void addNewConnection(PlayerConnection pc)
{
	synchronized (g_conMut)
		g_freshConnections ~= pc;
}

/// try to authorize the connection. If successfull, PlayerContext is assigned
/// to the connection.
bool confirmConnection(PlayerConnection pc)
{
	PlayerContext ctx = getOrCreatePlayerCtx(pc.username);
	bool existed = ctx.connection !is null;
	if (existed)
	{
		PlayerConnection econ = ctx.connection;
		if (ctx.password != pc.password)
			return false;
		info("Closing previous connection of this user");
		econ.closeSync("Another client has authorized");
	}
	ctx.connection = pc;
	pc.playerCtx = ctx;
	ctx.password = pc.password;
	trace("Number of authorized connections: ", g_players.length);
	synchronized (g_conMut)
		g_freshConnections.removeFirstUnstable(pc);
	return true;
}

/// remove connection from player's context or g_freshConnections
void removeConnection(PlayerConnection pc)
{
	if (pc.playerCtx !is null)
	{
		pc.playerCtx.connection = null;
		pc.playerCtx = null;
	}
	else
	{
		synchronized (g_conMut)
			g_freshConnections.removeFirstUnstable(pc);
	}
}