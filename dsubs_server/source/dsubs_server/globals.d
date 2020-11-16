module dsubs_server.globals;

import std.parallelism;
import core.sync.rwmutex;

import dsubs_sound.opencl;

import dsubs_server.player: PlayerCollection;
import dsubs_server.bots: BotCollection;
import dsubs_server.dynamics: PhysicalEnv;
import dsubs_server.connections.database;
import dsubs_server.connections.metrics;
import dsubs_server.acoustics;
import dsubs_server.common;
import dsubs_server.vessel: VesselCollection;
import dsubs_server.animal: AnimalCollection;
import dsubs_server.torpedo: WeaponCollection;
import dsubs_server.entitydb: EntityDb;
import dsubs_server.simulator: Simulator, SimulatorScheduler;
import dsubs_server.scenario;
import dsubs_server.connections.listener: ConListener;


/// Global references to most objects that comprise the server state and are
/// needed practically everywhere.
final abstract class Globals
{
__gshared:
	/// Global task pool that is used during simulation.
	TaskPool taskPool;
	/// Auxiliarry non-simulation-critical asynchronous tasks are put to this pool queue.
	TaskPool auxTaskPool;
	/// Library of all existing submarine types, propulsors and other unit types,
	/// irrespective of the scenatio.
	EntityDb entityDb;
	/// Collection of scenario factories and player-scenario controllers.
	ScenarioDatabase scenarioDb;
	/// Players that were authorized at least once.
	PlayerCollection players;
	/// TCP listeners
	ConListener cons;
	/// Collection of simulators.
	SimulatorScheduler simulators;
	/// OpenCL context. The point of multiplexed dsubs_server is to give
	/// the game more control over the resource allocation and keep it
	/// monolithic. Shared opencl context reduces VRAM usage and GPU overhead.
	DsubsSoundOpenclCtx sctx;
	/// Database (MariaDB) connector
	DatabaseService database;
	/// Metrics (InfluxDB) connector
	MetricsService metrics;

	static void build()
	{
		taskPool = new TaskPool(totalCPUs - 1);
		auxTaskPool = new TaskPool(totalCPUs - 1);
		trace("totalCPUs = ", totalCPUs);
		sctx = new DsubsSoundOpenclCtx(totalCPUs);
		entityDb = new EntityDb();
		scenarioDb = new ScenarioDatabase();
		players = new PlayerCollection();
		cons = new ConListener();
		simulators = new SimulatorScheduler(false);
	}

	/// helper method for idempotent preparation of globals
	/// for a test run. Returns a new empty simulator that is added
	/// to simulators tree.
	static Simulator buildForTests()
	{
		taskPool = new TaskPool(0);//totalCPUs - 1);
		auxTaskPool = new TaskPool(1);
		if (sctx is null)
			sctx = new DsubsSoundOpenclCtx(1);
		if (entityDb is null)
			entityDb = new EntityDb();
		if (scenarioDb is null)
			scenarioDb = new ScenarioDatabase();
		if (simulators is null)
			simulators = new SimulatorScheduler(true);
		else
			simulators.clear();
		Simulator sim = new Simulator();
		sim.printTimings = false;
		sim.doSleep = false;
		sim.runWithoutPlayers = true;
		simulators.add(sim);
		return sim;
	}

	static void resetForTests()
	{
		if (!simulators.joined)
		{
			simulators.stop();
			// simulators.join();
		}
		taskPool.finish(true);
		auxTaskPool.finish(true);
		simulators = null;
	}

	shared static ~this()
	{
		if (sctx)
		{
			sctx.release();
		}
	}
}
