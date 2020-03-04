module dsubs_server.simulator;

import std.container.rbtree: RedBlackTree;
import std.datetime;
import std.parallelism: task;
import std.uuid;

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
import dsubs_server.player: Player;
import dsubs_server.dynamics;
import dsubs_server.globals;



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

		alias SimulatorSchedTree = RedBlackTree!(Simulator,
			(a, b) => (a.nextStart < b.nextStart) || (a.nextStart == b.nextStart && a.id < b.id), false);
		// warning: rbtree assumes that the key is immutable. When we change nextStart
		// we must remove the sim from the tree, update it and re-insert it back.
		SimulatorSchedTree m_simulators;
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
	}

	/// Thread-safe removal of the simulator.
	void remove(Simulator s)
	{
		synchronized(m_cond.mutex)
		{
			if (m_simulators.removeKey(s))
				m_cond.notify();
		}
	}

	this(bool exitOnEmpty = false)
	{
		m_exitOnEmpty = exitOnEmpty;
		m_simulators = new SimulatorStartTree();
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
				synchronized(m_cond.mutex)
					m_simulators.removeKey(simToRun);
			}
			else
			{
				MonoTime newNextStart;
				if (simToRun.doSleep)
				{
					if (late > msecs(20))
					{
						warning("Simulator loop stalling");
						// self-distributing
						newNextStart = now + msecs(uniform!"[]"(0, 10));
					}
					else
						newNextStart = simToRun.nextStart +
							msecs((1000 / simToRun.acceleration).to!uint);
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

	private usecs_t m_worldTime = 0;
	@property usecs_t worldTime() const { return m_worldTime; }

	/// simulator will report as finished when it's wordTime exceeds worldTimeLimit.
	usecs_t worldTimeLimit = usecs_t.max;
	@property bool finished() const { return m_worldTime > worldTimeLimit; }

	/// print stage timings to log
	bool printTimings = false;

	/// Simulator wants to be scheduled at this time or slightly after it.
	private MonoTime nextStart;

	/// if false, this is a greedy simulator that does not need periodic
	/// scheduling and wants to be ran as often as possible (subject to fairness constraints).
	bool doSleep = true;

	/// time acceleration factor.
	float acceleration = 1.0f;

	Event!(void delegate(usecs_t now)) onSimulationPassStart;
	Event!(void delegate(usecs_t now)) onSimulationPassEnd;

	/// run one iteration of simulation
	private void runOnce(ProfTimer profiler)
	{
		synchronized (simMut.writer)
		{
			// some user actions enqueue buffer commands on first queue,
			// we need to wait for their completion.
			Globals.sctx.queue(0).finish();
			profiler.start();
			profiler.start("onSimulationPassStart");
			onSimulationPassStart(m_worldTime);
			profiler.stopLast();
			if (Globals.scenario)
			{
				profiler.start("scenario.onBeforeSimulation");
				Globals.scenario.onBeforeSimulation();
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
			vessels.collectDeadVessels();
			profiler.stopLast();
			profiler.start("bots.onAfterSimulation");
			bots.onAfterSimulation();
			profiler.stopLast();
			if (scenario)
			{
				profiler.start("scenario.onAfterSimulation");
				scenario.onAfterSimulation();
				profiler.stopLast();
			}
			if (Globals.players)
			{
				// stream updates to players
				profiler.start("players.forEachPlayer.sendUpdate");
				Globals.players.forEachPlayer((p) { p.sendUpdate(); });
				profiler.stopLast();
			}
			profiler.start("onSimulationPassEnd");
			onSimulationPassEnd(m_worldTime);
			profiler.stopLast();
		}
		profiler.stop();
		if (printTimings)
			profiler.printResult();
		if (Globals.metrics && (m_worldTime % 10_000_000 == 0))
		{
			Globals.auxTaskPool.put(
				task(&Globals.metrics.writeMetrics,
						profiler, Player.getPlayersOnline()));
			// do not send data to influx when no-one is here
			if (Player.getPlayersOnline)
			{
				Globals.auxTaskPool.put(
					task(&Globals.metrics.writeReplayData));
			}
		}
	}
}
