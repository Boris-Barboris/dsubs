module dsubs_server.globals;

import std.parallelism;
import core.sync.rwmutex;

import dsubs_sound.opencl;

import dsubs_server.player: PlayerCollection;
import dsubs_server.dynamics: PhysicalEnv;
import dsubs_server.acoustics;
import dsubs_server.entitydb: EntityDb;
import dsubs_server.simulator: Simulator;
import dsubs_server.connections.listener: ConListener;


/// Global references to most objects that comprise the server state and are
/// needed practically everywhere.
final abstract class Globals
{
__gshared:
	/// Main simulation RW-mutex that guards game state. Write-lock is taken
	/// by the server when the world needs to freeze.
	ReadWriteMutex simMut;
	/// Global task pool.
	TaskPool taskPool;

	/// Library of submarine types, propulsors and other unit types
	EntityDb entityDb;
	/// players that were authorized at least once.
	PlayerCollection players;
	/// TCP listeners
	ConListener cons;
	/// Physics engine
	PhysicalEnv phys;
	/// Acoustics engine
	AcousticEnv acous;
	/// Simulator
	Simulator sim;
	/// OpenCL context
	DsubsSoundOpenclCtx sctx;

	static void build()
	{
		simMut = new ReadWriteMutex();
		taskPool = new TaskPool(totalCPUs - 1);
		sctx = new DsubsSoundOpenclCtx(totalCPUs);
		entityDb = new EntityDb();
		players = new PlayerCollection();
		cons = new ConListener();
		phys = new PhysicalEnv();
		acous = new AcousticEnv();
		sim = new Simulator();
	}
}