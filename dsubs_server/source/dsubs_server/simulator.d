/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.simulator;

import std.container.rbtree: RedBlackTree;
import std.datetime;
import std.parallelism: task;
import std.range: walkLength;
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
import dsubs_common.api.entities: ScenarioType;
import dsubs_common.api.deventities;
import dsubs_common.api.deventities: SimulatorRecord;

import dsubs_server.common;
import dsubs_server.acoustics;
import dsubs_server.animal;
import dsubs_server.bots;
import dsubs_server.email;
import dsubs_server.dynamics;
import dsubs_server.submarine: Submarine;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player: Player;
import dsubs_server.torpedo;
import dsubs_server.scenario;
import dsubs_server.weaponry;



/// Collection of simulators that can be ran in time-sharing manner in one
/// dsubs_server process. Only one simulator runs at any point in time.
final class SimulatorScheduler
{
	private
	{
		/// Main simulation thread. Simulators fork-n-join inside their component systems
		/// a lot, so there is little incentive to run a thread per simulator.
		/// One main thread is enough. In fact, it's easier with one main thread.
		Thread m_thread;
		/// Condition variable to block on when there is no simulator to run.
		/// It's mutex guards m_simulators tree from concurrent access.
		Condition m_cond;
		bool m_stopFlag;
		bool m_joined;
		bool m_started;

		alias SimulatorScheduleTree = RedBlackTree!(Simulator,
			(a, b) => (a.nextStart < b.nextStart) || (a.nextStart == b.nextStart && a.id < b.id), false);
		// warning: rbtree assumes that the key is immutable. When we change nextStart
		// we must remove the sim from the tree, update the key and re-insert it back.
		SimulatorScheduleTree m_simulators;
	}

	/// Thread-safe addition of a simulator instance to scheduling queue.
	/// Simulator is scheduled to run immediately.
	void add(Simulator s)
	{
		s.nextStart = MonoTime.currTime();
		try
		{
			if (Globals.database)
				Globals.database.insertNewSimulatorInstance(s);
		}
		catch (Exception ex)
		{
			error("database error: ", ex.toString());
		}
		synchronized(m_cond.mutex)
		{
			m_simulators.stableInsert(s);
			m_cond.notify();
		}
		trace("added ", s.id, " simulator to scheduler");
	}

	/// Thread-safe removal of the simulator. Generally, it's better
	/// to let scheduler himself remove finished sims from the tree.
	void remove(Simulator s)
	{
		bool removed;
		synchronized(m_cond.mutex)
		{
			if (m_simulators.removeKey(s))
			{
				removed = true;
				m_cond.notify();
				trace("removed ", s.id, " simulator from scheduler");
			}
		}
		try
		{
			if (removed && Globals.database)
				Globals.database.markSimulatorDestroyed(
					s.uniqId, "SimulatorScheduler.remove");
		}
		catch (Exception ex)
		{
			error("database error: ", ex.toString());
		}
	}

	Simulator findByUniqId(string uniqId)
	{
		synchronized(m_cond.mutex)
		{
			foreach (sim; m_simulators[])
			{
				if (sim.uniqId == uniqId)
					return sim;
			}
		}
		return null;
	}

	SimulatorRecord[] listSimulators()
	{
		SimulatorRecord[] res;
		synchronized(m_cond.mutex)
		{
			foreach (sim; m_simulators[])
			{
				res ~= getSimRecordForSim(sim);
			}
		}
		return res;
	}

	static SimulatorRecord getSimRecordForSim(Simulator sim)
	{
		SimulatorRecord simRec;
		simRec.id = sim.id;
		simRec.uniqId = sim.uniqId;
		if (sim.scenario)
		{
			simRec.scenarioName = sim.scenario.name;
		}
		simRec.connectedPlayers = sim.getConnectedPlayers();
		simRec.creatorPlayerName = sim.creatorPlayerName;
		return simRec;
	}

	this(bool exitOnEmpty = false)
	{
		m_exitOnEmpty = exitOnEmpty;
		m_simulators = new SimulatorScheduleTree();
		m_cond = new Condition(new Mutex());
		m_thread = new Thread(&schedulingLoop);
	}

	/// start the main thread
	void start()
	{
		m_started = true;
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
	/// no simulator to run. Useful for tests.
	private bool m_exitOnEmpty;

	@property bool joined() const { return m_joined; }

	/// Request to stop the simulation loop.
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
		if (m_started)
		{
			m_thread.join();
			m_joined = true;
		}
	}

	// main function that runs simulators in a loop
	private void schedulingLoop()
	{
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
			string evictReason;
			try
			{
				simToRun.runOnce();
			}
			catch (Throwable e)
			{
				error("Simulator ", simToRun.id, " crashed: ", e.toString());
				sendMail("dsubs_server simulator crash", e.msg);
				simToRun.terminateAsync();
				// eager attempt to evict players
				simToRun.runOnce();
				evictReason = "crash";
			}
			if (simToRun.finished)
			{
				if (evictReason == null)
					evictReason = "finished";
				trace("Evicting ", simToRun.id, " finished simulator from scheduler");
				synchronized(m_cond.mutex)
					m_simulators.removeKey(simToRun);
				simToRun.releaseResources();
				try
				{
					if (Globals.database)
						Globals.database.markSimulatorDestroyed(
							simToRun.uniqId, evictReason);
				}
				catch (Exception ex)
				{
					error("database error: ", ex.toString());
				}
				// recreate main_arena (special case)
				if (simToRun.scenario &&
					simToRun.scenario.spawner.scenarioType == ScenarioType.persistentSimulator)
				{
					auto spawner = Globals.scenarioDb.getPersistentById(simToRun.id);
					spawner.recreateSimulator();
					Globals.scenarioDb.startPersistentSimulator(simToRun.id);
				}
			}
			else
			{
				MonoTime newNextStart;
				if (simToRun.doSleep)
				{
					Duration expectedInterval = msecs(
						(1000 * 10 / simToRun.timeAccelerationFactor).to!uint);
					if (late > msecs(50))
					{
						warning("Simulator loop stalling for ", late);
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
					// reinsert the sim to the tree
					m_simulators.removeKey(simToRun);
					simToRun.nextStart = newNextStart;
					m_simulators.stableInsert(simToRun);
				}
			}
		}
	}
}


/// Simulator instance, one game world.
final class Simulator
{
	private string m_id, m_uniqId;
	/// non-historically unique, used for per-process uniqueness. Example: 'main_arena'.
	@property string id() const { return m_id; }
	/// historically-unique (across all simulators that ever existed), random UUID.
	@property string uniqId() const { return m_uniqId; }

	public
	{
		/// Main simulation RW-mutex that guards game state. Write-lock is taken
		/// by the server when the world is updated. Reader lock is taken by
		/// external threads, for example player connections, when the world is
		/// frozen and can be updated.
		ReadWriteMutex simMut;

		// Entity systems:

		/// Physics system, rigid bodies etc.
		PhysicalEnv phys;
		/// Acoustics entity collection
		AcousticEnv acous;
		/// Active vessels
		VesselCollection vessels;
		/// Active animals
		AnimalCollection animals;
		/// Active weapons
		WeaponCollection weapons;
		/// Active bots
		BotCollection bots;

		/// Scenario object, should be constructed/assigned by the external code.
		Scenario scenario;
	}

	private
	{
		/// Reference counter, number of connected players that have non-dead
		/// m_submarine in this simulator.
		shared int m_connectedPlayers;

		string m_creatorPlayerName;

		/// set of observers
		Player[string] m_observers;
	}

	int getConnectedPlayers() const { return atomicLoad(m_connectedPlayers); }

	void incConnectedPlayers() { atomicOp!"+="(m_connectedPlayers, 1); }

	@property string creatorPlayerName() const { return m_creatorPlayerName; }

	void decConnectedPlayers()
	{
		int result = atomicOp!"-="(m_connectedPlayers, 1);
		assert(result >= 0);
	}

	// returns the removed player or null if there was no such observer
	Player unregisterObserver(string username)
	{
		synchronized(this)
		{
			Player* res = username in m_observers;
			if (m_observers.remove(username))
			{
				res.unsetObservedSimulator();
				return *res;
			}
			return null;
		}
	}

	void registerObserver(Player player)
	{
		assert(player.submarine is null);
		synchronized(this)
		{
			Player* res = player.username in m_observers;
			if (m_observers.remove(player.username))
			{
				// TODO: maybe need some proper eviction
				res.unsetObservedSimulator();
			}
			m_observers[player.username] = player;
		}
	}

	/// id will be a random UUID string if left as null.
	this(string id = null, string creatorPlayerName = null)
	{
		m_uniqId = randomUUID().toString();
		if (id is null)
			id = m_uniqId;
		m_id = id;
		m_creatorPlayerName = creatorPlayerName;
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

	/// Request termination. It's scheduler's job to evict it.
	/// If called not by the scheduler, sim's reader lock must be held.
	void terminateAsync()
	{
		m_terminating = true;
	}

	private bool m_terminating;

	/// simulator will report as finished when it's wordTime exceeds worldTimeLimit, or
	/// when it's asked to terminate (by scenario, for example).
	usecs_t worldTimeLimit = usecs_t.max;

	@property bool finished() const
	{
		return m_terminating || m_worldTime > worldTimeLimit;
	}

	/// print stage timings to server log
	bool printTimings = false;

	/// Simulator wants to be scheduled at this time or slightly after it.
	private MonoTime nextStart;

	/// if false, this is a greedy simulator that does not need periodic
	/// scheduling and wants to be ran as often as possible
	/// (subject to fairness constraints).
	bool doSleep = true;

	/// Set to true if this is a real-time simulator that needs to proceed even without
	/// player observers.
	bool runWithoutPlayers = false;

	// 10 is normal, 5 is half-speed, 80 is 8x
	private short m_timeAccelerationFactor = 10;

	// edge flag to trigger the send of messages
	private bool m_timeAccelerationFactorChanged;

	@property short timeAccelerationFactor() const { return m_timeAccelerationFactor; }

	/// Must be called while holding simMut.reader
	@property void timeAccelerationFactor(short rhs)
	{
		enforce(canBePaused, "Cannot change timeAccelerationFactor of simulator " ~ id);
		// use doSleep = false if you need no actual pause between simulation steps.
		enforce(rhs > 0 && rhs < 1000, "Insane time acceleration factor proposed");
		m_timeAccelerationFactorChanged = true;
		m_timeAccelerationFactor = rhs;
		// trace("Setting simulator ", m_id, " acceleration factor to ", rhs);
	}

	bool canBePaused = true;

	private bool m_paused;
	// edge flag to trigger the send of messages
	private bool m_pausedChanged;

	@property bool paused() const { return m_paused; }

	/// Must be called while holding simMut.reader
	@property void paused(bool rhs)
	{
		enforce(canBePaused, "Cannot change paused state of simulator " ~ id);
		m_pausedChanged = true;
		m_paused = rhs;
	}

	// events, called synchronously from scheduler's thread, with sim's
	// writer lock being held.
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
		// parallelize, some functions in sendUpdate are blocking/heavy.
		foreach (SubPlayerPair pair; Globals.taskPool.parallel(playersToUpdate, 1))
		{
			pair.player.sendUpdate(pair.sub);
		}
	}

	/// All players that own vessels in this sim receive pause/unpause notification.
	private void sendPauseUpdateToPlayers()
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
			pair.player.sendPauseStateUpdate(pair.sub, m_paused);
		}
	}

	/// All players that own vessels in this sim receive new time acceleration factor.
	private void sendTimeAccelUpdateToPlayers()
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
			pair.player.sendTimeAccelerationFactorUpdate(
				pair.sub, m_timeAccelerationFactor);
		}
	}

	/// All players that own non-dead vessels in this sim receive message.
	private void sendTerminatingToPlayers()
	{
		foreach (Submarine sub; vessels.submarines)
		{
			if (sub && sub.player)
				sub.player.handleSimTerminating(sub);
		}
	}

	/// Ask most subsystems to shutdown everything and release resources
	private void releaseResources()
	{
		synchronized (simMut.reader)
		{
			weapons.shutdownAll();
			vessels.shutdownAll();
			animals.shutdownAll();
			acous.clean();
		}
		Globals.sctx.runWavFileGC();
	}

	private
	{
		// number of runs with no connected players
		long m_abandonedCounter;
		// 21 days in there is no time acceleration.
		// TODO: limit total number of simulators. Simulator eviction.
		enum long ABANDON_COUNT_LIMIT = 60 * 60 * 24 * 21;
	}

	/// run one iteration of simulation
	private void runOnce()
	{
		// this block handles simulator stuttering when there is noone connected
		// to it and terminating when a lot of time has passed.
		if (!runWithoutPlayers && getConnectedPlayers() == 0 && !m_terminating)
		{
			m_abandonedCounter++;
			if (m_abandonedCounter >= ABANDON_COUNT_LIMIT)
				terminateAsync();
			else
				return;
		}
		m_abandonedCounter = 0;
		ProfTimer profiler = ProfTimer();
		synchronized (simMut.writer)
		{
			// early exit
			if (m_terminating)
			{
				sendTerminatingToPlayers();
				return;
			}
			// pause handling
			if (m_pausedChanged)
			{
				// edge-triggered update to players
				m_pausedChanged = false;
				sendPauseUpdateToPlayers();
			}
			if (m_timeAccelerationFactorChanged)
			{
				// edge-triggered update to players
				m_timeAccelerationFactorChanged = false;
				sendTimeAccelUpdateToPlayers();
			}
			if (m_paused)
			{
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
				// scenario might want to initialize the world before anything moves
				scenario.onBeforeSimulation();
				profiler.stopLast();
			}
			profiler.start("vessels.preKinematics");
			vessels.preKinematics();
			profiler.stopLast();
			profiler.start("acous.preKinematics");
			// sound stuff needs starting positions and velocities
			acous.preKinematics();
			profiler.stopLast();
			profiler.start("phys.integratePBodies");
			// physics integration. All rigid bodies are moved.
			phys.integratePBodies(1.0f, 0.25f);
			profiler.stopLast();
			m_worldTime += 1000_000;
			profiler.start("acous.postKinematics");
			// sound stuff needs final positions and velocities
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
			profiler.start("animals.collectDeadAnimals");
			animals.collectDeadAnimals();
			profiler.stopLast();
			profiler.start("bots.onAfterSimulation");
			bots.onAfterSimulation();
			profiler.stopLast();
			if (scenario)
			{
				profiler.start("scenario.onAfterSimulation");
				ShouldSimTerminate sst = scenario.onAfterSimulation(1000_000);
				profiler.stopLast();
				if (sst == ShouldSimTerminate.yes)
				{
					info("Terminating simulator by scenario sst: ", id);
					m_terminating = true;
				}
			}
			// send updates to players
			profiler.start("sendUpdateToPlayers");
			// scenario is responsible for sending termination messages based on
			// the reason of sim shutdown. Simulator should not know about victory/loss.
			// Look at scenario.sendChangesOrFinish.
			sendUpdateToPlayers();
			profiler.stopLast();
			// send updates to observers
			profiler.start("sendUpdateToObservers");
			sendUpdateToObservers();
			profiler.stopLast();
			// additional logic for time-based termination
			if (finished)
				sendTerminatingToPlayers();
			profiler.start("onSimulationPassEnd");
			onSimulationPassEnd(this, m_worldTime);
			profiler.stopLast();
		}
		profiler.stop();
		if (printTimings)
			profiler.printResult();
		if (!finished &&
			Globals.metrics && (m_worldTime % 10_000_000 == 0))
		{
			if (scenario)
			{
				// influxdb metrics
				if (this.id == "main_arena")
				{
					// player count should only be written once per 10 secs, hence the
					// main_arena filter
					Globals.auxTaskPool.put(
						task(&Globals.metrics.writePlayerStats, Player.getPlayersOnline()));
				}
				// do not write replay to influx when there are no non-dead player subs
				if (vessels.alivePlayerSubmarines.walkLength)
				{
					Globals.auxTaskPool.put(
						task(&Globals.metrics.writeReplayData, this));
				}
			}
			Globals.auxTaskPool.put(
				task(&Globals.metrics.writeSimulatorMetrics, id, profiler));
		}
	}

	// reader lock must be held
	ObservableEntityUpdate[] getObservableEntities()
	{
		ObservableEntityUpdate[] res;
		res.reserve(32);
		vessels.appendObserverEntityUpdates(res);
		return res;
	}

	/// All players that own vessels in this sim receive update.
	/// Sim writer lock is held.
	private void sendUpdateToObservers()
	{
		Player[] playersToSendUpdateTo;
		foreach (Player p; m_observers.byValue)
		{
			if (p.connection && p.connection.isOpen &&
					p.connection.simulatorFlow)
				playersToSendUpdateTo ~= p;
		}
		if (playersToSendUpdateTo.length > 0)
		{
			ObservableEntityUpdate[] entityUpdates = getObservableEntities();
			// parallelize, some functions in sendUpdate are blocking/heavy.
			foreach (Player p; Globals.taskPool.parallel(
				playersToSendUpdateTo, 1))
			{
				p.sendObserverUpdate(entityUpdates, [], m_worldTime);
			}
		}
	}
}
