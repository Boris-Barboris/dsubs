module dsubs_server.player;

import std.math;

import core.sync.mutex;

import dsubs_common.api;
import dsubs_common.containers.array;
import gfm.math.vector;

import dsubs_server.common;
import dsubs_server.connection: PlayerConnection;
import dsubs_server.submarine;
import dsubs_server.rng;


/// This structure hold player information. It is expected to always be
/// mutated by one thread only
final class PlayerContext
{
	this(string uname)
	{
		username = uname;
		coordShift = vec2d(uniform(-30000.0, 30000.0), uniform(-30000.0, 30000.0));
		coordRot = uniform(-PI, PI);
		timeShift = uniform(-200_000_000L, 200_000_000L);
	}

	const string username;
	string password;
	bool isBot = false;
	bool isAdmin = false;

	// maybe not needed
	int playerKillCount;
	int botKillCount;
	int deathCount;

	/// obfuscating reference frame origin shift
	vec2d coordShift;
	/// obfuscating reference frame rotation
	double coordRot;
	/// obfuscating world time shift
	usecs_t timeShift;

	/// current active connection to this player, null if none
	PlayerConnection connection;

	/// player's submarine (null if he doesn't have one yet)
	Submarine submarine;

	/// send the player kinematic information of his submarine
	void sendKinematicsUpdate(usecs_t curTime)
	{
		if (connection is null || submarine is null)
			return;
		vec2d shiftedPos = submarine.transform.position + coordShift;
		double shiftedRot = submarine.transform.rotation + coordRot;
		immutable(SubKinematicRes)* msg = new SubKinematicRes(KinematicSnapshot(
			curTime + timeShift,
			Vector2d(shiftedPos.x, shiftedPos.y),
			submarine.rigidBody.kinet.velLength,
			shiftedRot));
		connection.sendMessage(msg);
	}
}


/// randomizes position and rotation of a submarine
void randomizePosition(Submarine sub)
{
	double px = uniform(-100.0, 100);
	double py = uniform(-100.0, 100);
	double rot = uniform(-PI, PI);
	sub.transform.position = vec2d(px, py);
	sub.transform.rotation = rot;
	sub.rigidBody.updateFromTransform();
}


private __gshared PlayerContext[string] g_players;
/// mutex that guards g_players
private shared Mutex g_playerMut;

/// all unauthorized connections
private __gshared PlayerConnection[] g_freshConnections;
/// mutex that guards g_freshConnections
private shared Mutex g_conMut;

/// initialize all globals, responsible for connection and player context
/// managment
void s_initializePlayersCtx()
{
	info("Initializing player context mutexts");
	g_playerMut = new shared Mutex();
	g_conMut = new shared Mutex();
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

/// apply delegate dlg to each player context
void forEachPlayer(scope void delegate(PlayerContext) dlg)
{
	synchronized (g_playerMut)
	{
		foreach (PlayerContext pc; g_players.values)
			dlg(pc);
	}
}