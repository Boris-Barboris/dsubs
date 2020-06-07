module dsubs_server.simulator;

import std.container.rbtree: RedBlackTree;
import std.datetime;
import std.parallelism: task;
import std.uuid;

import core.atomic;
import core.time: MonoTime;
import core.thread;
import core.memory;
import core.sync.rwmutex;
import core.sync.condition: Condition;
import core.sync.mutex: Mutex;
import core.stdc.stdlib;

import dsubs_common.proftimer;
import dsubs_common.event;

import dsubs_server.common;
import dsubs_server.acoustics;
import dsubs_server.animal;
import dsubs_server.bots;
import dsubs_server.dynamics;
import dsubs_server.submarine: Submarine;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player: Player;
import dsubs_server.torpedo;
import dsubs_server.scenario;
import dsubs_server.weaponry;



/// Collection of simulators that can be ran in time-sharing manner in one
/// dsubs_server process.
final class SimulatorScheduler
{
	private
	{
		/// main simulation thread. Simulators fork-n-join inside a lot, so there is
		/// little incentive to run a thread per simulator. One main thread is enough.
		Thread m_thread;
		/// Condition to block on when there is no simulator to run.
		Condition m_cond;
		bool m_stopFlag;
		bool m_joined;

		alias SimulatorDeadlineTree = RedBlackTree!(Simulator,
			(a, b) => (a.nextStart < b.nextStart) || (a.nextStart == b.nextStart && a.id < b.id), false);
		// warning: rbtree assumes that the key is immutable. When we change nextStart
		// we must remove the sim from the tree, update the key and re-insert it back.
		SimulatorDeadlineTree m_simulators;
	}

	/// Thread-safe addition of a simulator instance to scheduling queue.
	/// Simulator is scheduled to run immediately.
	void add(Simulator s)
	{
		s.nextStart = MonoTime.currTime();
		synchronized(m_cond.mutex)
		{
			m_simulators.stableInsert(s);
			m_cond.notify();
		}
		trace("added ", s.id, " simulator to scheduler");
	}

	/// Thread-safe removal of the simulator.
	void remove(Simulator s)
	{
		synchronized(m_cond.mutex)
		{
			if (m_simulators.removeKey(s))
			{
				m_cond.notify();
				trace("removed ", s.id, " simulator from scheduler");
			}
		}
	}

	this(bool exitOnEmpty = false)
	{
		m_exitOnEmpty = exitOnEmpty;
		m_simulators = new SimulatorDeadlineTree();
		m_cond = new Condition(new Mutex());
		m_thread = new Thread(&schedulingLoop);
	}

	/// start the main thread
	void start()
	{
		m_thread.start();
	}

	/// remove all simulators from the tree
	void clear()
	{
		synchronized(m_cond.mutex)
		{
			m_simulators.clear();
			m_cond.notify();
		}
	}

	/// Set to true if the sim thread should exit when there is
	/// no simulator to run.
	private bool m_exitOnEmpty;

	@property bool joined() const { return m_joined; }

	/// request to stop the simulation loop.
	void stop()
	{
		m_stopFlag = true;
		synchronized(m_cond.mutex)
			m_cond.notify();
	}

	/// rethrows the exception.
	void join()
	{
		assert(!m_joined, "already joined");
		m_thread.join();
		m_joined = true;
	}

	private void schedulingLoop()
	{
		ProfTimer profiler = new ProfTimer();
		scope(success) info("simulator thread exiting");
		while (!m_stopFlag)
		{
			Simulator simToRun;
			synchronized(m_cond.mutex)
			{
				if (m_simulators.length)
					simToRun = m_simulators.front();
				else
				{
					if (m_exitOnEmpty)
						return;
					// wait for tree change or a stop signal.
					m_cond.wait();
					continue;
				}
			}
			assert(simToRun);
			MonoTime now = MonoTime.currTime();
			if (now < simToRun.nextStart)
			{
				// we woke up too early
				Duration toSleep = simToRun.nextStart - now;
				synchronized(m_cond.mutex)
				{
					if (m_cond.wait(toSleep))
						continue;	// tree has changed or the stop signal
				}
				now = MonoTime.currTime();
			}
			Duration late = now - simToRun.nextStart;
			// the time has come
			simToRun.runOnce(profiler);
			// now we calculate the next wakeup or remove the sim from tree
			if (simToRun.finished)
			{
				trace("Evicting ", simToRun.id, " finished simulator from scheduler");
				synchronized(m_cond.mutex)
					m_simulators.removeKey(simToRun);
			}
			else
			{
				MonoTime newNextStart;
				if (simToRun.doSleep)
				{
					Duration expectedInterval = msecs(
						(1000 / simToRun.timeAcceleration).to!uint);
					if (late > msecs(20))
					{
						warning("Simulator loop stalling");
						// schedule skew
						newNextStart = now + expectedInterval;
					}
					else
						newNextStart = simToRun.nextStart + expectedInterval;
				}
				else
					newNextStart = MonoTime.currTime;
				synchronized(m_cond.mutex)
				{
					// reinsert the sim
					m_simulators.removeKey(simToRun);
					simToRun.nextStart = newNextStart;
					m_simulators.stableInsert(simToRun);
				}
			}
		}
	}
}


/// Simulator instance, that constitutes one particular game world.
final class Simulator
{
	private string m_id;
	@property string id() const { return m_id; }

	public
	{
		/// Main simulation RW-mutex that guards game state. Write-lock is taken
		/// by the server when the world needs to freeze.
		ReadWriteMutex simMut;
		/// Physics system with rigid modies
		PhysicalEnv phys;
		/// Acoustics entity collection
		AcousticEnv acous;
		/// Active vessels
		VesselCollection vessels;
		/// Active animals
		AnimalCollection animals;
		/// Active weapons
		WeaponCollection weapons;
		/// All active bots
		BotCollection bots;

		/// Scenario object, should be constructed by the external code.
		Scenario scenario;

		/// Reference counter, number of connected players that have a
		/// m_submarine in this simulator.
		shared int m_connectedPlayers;
	}

	int getConnectedPlayers() const { return atomicLoad(m_connectedPlayers); }

	void incConnectedPlayers() { atomicOp!"+="(m_connectedPlayers, 1); }

	void decConnectedPlayers()
	{
		int result = atomicOp!"-="(m_connectedPlayers, 1);
		assert(result >= 0);
	}

	/// id will be a random UUID string if not specified.
	this(string id = null)
	{
		if (id is null)
			id = randomUUID().toString();
		m_id = id;
		simMut = new ReadWriteMutex();
		phys = new PhysicalEnv();
		acous = new AcousticEnv();
		vessels = new VesselCollection();
		animals = new AnimalCollection();
		weapons = new WeaponCollection();
		bots = new BotCollection();
	}

	// calculate the number of players that are connected to the submarines in
	// this simulator.
	// int getConnectedPlayers() const
	// {
	// 	int res = 0;
	// 	foreach (const Submarine sub; vessels.submarines)
	// 	{
	// 		if (sub && sub.player && sub.player.connection &&
	// 			sub.player.connection.isOpen)
	// 			res++;
	// 	}
	// 	return res;
	// }

	private usecs_t m_worldTime = 0;
	@property usecs_t worldTime() const { return m_worldTime; }

	// Must be called while holding simMut.
	void terminateAsync()
	{
		m_terminating = true;
	}

	private bool m_terminating;
	/// simulator will report as finished when it's wordTime exceeds worldTimeLimit, or
	/// when it's asked to terminate by scenario.
	usecs_t worldTimeLimit = usecs_t.max;
	@property bool finished() const
	{
		return m_terminating || m_worldTime > worldTimeLimit;
	}

	/// print stage timings to log
	bool printTimings = false;

	/// Simulator wants to be scheduled at this time or slightly after it.
	private MonoTime nextStart;

	/// if false, this is a greedy simulator that does not need periodic
	/// scheduling and wants to be ran as often as possible (subject to fairness constraints).
	bool doSleep = true;

	/// Set to true if this is a real-time simulator that needs to proceed even without
	/// player observers.
	bool runWithoutPlayers = false;

	float timeAcceleration = 1.0f;

	Event!(void delegate(Simulator sim, usecs_t now)) onSimulationPassStart;
	Event!(void delegate(Simulator sim, usecs_t now)) onSimulationPassEnd;

	/// All players that own vessels in this sim receive update.
	private void sendUpdateToPlayers()
	{
		static struct SubPlayerPair
		{
			Player player;
			Submarine sub;
		}

		SubPlayerPair[] playersToUpdate;
		foreach (Submarine sub; vessels.submarines)
		{
			if (sub && sub.player)
				playersToUpdate ~= SubPlayerPair(sub.player, sub);
		}
		foreach (SubPlayerPair pair; Globals.taskPool.parallel(playersToUpdate, 1))
		{
			if (finished)
				pair.player.handleSimTerminating(pair.sub);
			else
				pair.player.sendUpdate(pair.sub);
		}
	}

	private
	{
		long m_abandonedCounter;
		// 3 days
		enum long ABANDON_COUNT_LIMIT = 60 * 60 * 24 * 3;
	}

	/// run one iteration of simulation
	private void runOnce(ProfTimer profiler)
	{
		if (!runWithoutPlayers && getConnectedPlayers() == 0)
		{
			m_abandonedCounter++;
			if (m_abandonedCounter >= ABANDON_COUNT_LIMIT)
				terminateAsync();
			else
				return;
		}
		m_abandonedCounter = 0;
		synchronized (simMut.writer)
		{
			// early exit
			if (m_terminating)
			{
				sendUpdateToPlayers();
				return;
			}
			// some user actions enqueue buffer commands on first queue,
			// we need to wait for their completion.
			Globals.sctx.queue(0).finish();
			profiler.start();
			profiler.start("onSimulationPassStart");
			onSimulationPassStart(this, m_worldTime);
			profiler.stopLast();
			if (scenario)
			{
				profiler.start("scenario.onBeforeSimulation");
				scenario.onBeforeSimulation();
				profiler.stopLast();
			}
			profiler.start("vessels.preKinematics");
			vessels.preKinematics();
			profiler.stopLast();
			profiler.start("acous.preKinematics");
			acous.preKinematics();
			profiler.stopLast();
			// physics integration. All rigid bodies are moved.
			profiler.start("phys.integratePBodies");
			phys.integratePBodies(1.0f, 0.25f);
			profiler.stopLast();
			m_worldTime += 1000_000;
			profiler.start("acous.postKinematics");
			acous.postKinematics(1.0f);
			profiler.stopLast();
			profiler.start("acous.processActiveSonars");
			acous.processActiveSonars();
			profiler.stopLast();
			profiler.start("acous.applySourcesOnHydrophones");
			acous.applySourcesOnHydrophones();
			profiler.stopLast();
			profiler.start("acous.postAcousticsUpdate");
			acous.postAcousticsUpdate();
			profiler.stopLast();
			profiler.start("weapons.updateGuidances");
			weapons.updateGuidances(1000_000);
			profiler.stopLast();
			profiler.start("vessels.postKinematics");
			vessels.postKinematics(1000_000);
			profiler.stopLast();
			profiler.start("animals.postKinematics");
			animals.postKinematics(1000_000);
			profiler.stopLast();
			profiler.start("vessels.collectDeadVessels");
			vessels.collectDeadVessels(worldTime);
			profiler.stopLast();
			profiler.start("bots.onAfterSimulation");
			bots.onAfterSimulation();
			profiler.stopLast();
			if (scenario)
			{
				profiler.start("scenario.onAfterSimulation");
				ShouldSimTerminate signal = scenario.onAfterSimulation();
				profiler.stopLast();
				if (signal == ShouldSimTerminate.yes)
				{
					info("Terminating simulator ", id);
					m_terminating = true;
				}
			}
			// send updates to players
			profiler.start("sendUpdateToPlayers");
			sendUpdateToPlayers();
			profiler.stopLast();
			profiler.start("onSimulationPassEnd");
			onSimulationPassEnd(this, m_worldTime);
			profiler.stopLast();
		}
		profiler.stop();
		if (printTimings)
			profiler.printResult();
		if (!finished && m_id == "main_arena" &&
			Globals.metrics && (m_worldTime % 10_000_000 == 0))
		{
			Globals.auxTaskPool.put(
				task(&Globals.metrics.writeMetrics,
						profiler, Player.getPlayersOnline()));
			// do not send data to influx when no-one is here
			if (Player.getPlayersOnline())
			{
				Globals.auxTaskPool.put(
					task(&Globals.metrics.writeReplayData, this));
			}
		}
	}
}
