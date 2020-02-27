module dsubs_server.simulator;

import std.datetime;
import std.parallelism: task;

import core.thread;
import core.memory;
import core.sync.rwmutex;
import core.stdc.stdlib;

import dsubs_common.proftimer;
import dsubs_common.event;

import dsubs_server.common;
import dsubs_server.player: Player;
import dsubs_server.dynamics;



/// Collection of simulators that can be ran in time-sharing manner.
final class SimulatorScheduler
{
	private
	{
		/// main simulation thread. Simulators fork-n-join inside a lot, so there is
		/// little incentive to run a thread per simulator. One main thread is enough.
		Thread m_thread;
		bool m_stopFlag;
		bool m_joined;
	}

	this()
	{
		m_thread = new Thread(&schedulingLoop);
	}

	void start()
	{
		m_thread.start();
	}

	@property bool joined() const { return m_joined; }

	/// request to stop the simulation loop.
	void stop()
	{
		m_stopFlag = true;
	}

	void join()
	{
		assert(!m_joined, "already joined");
		m_thread.join();
		m_joined = true;
	}
}


/// Simulator instance, that constitutes one particular game world.
final class Simulator
{
	private usecs_t m_worldTime = 0;
	@property usecs_t worldTime() const { return m_worldTime; }

	usecs_t worldTimeLimit = usecs_t.max;

	/// print stage timings to log or not
	bool printTimings = false;
	/// if false, this is a greedy simulator that does not need periodic
	/// scheduling and wants to be ran as often as possible and fair.
	bool doSleep = true;
	/// time acceleration factor of this simulator.
	float acceleration = 1.0f;

	Event!(void delegate(usecs_t now)) onSimulationPassStart;
	Event!(void delegate(usecs_t now)) onSimulationPassEnd;

	private void simulationLoop()
	{
		try
		{
			MonoTime loopStart = MonoTime.currTime();
			ProfTimer profiler = new ProfTimer();
			while (!m_stopFlag)
			{
				if (worldTimeLimit <= m_worldTime)
				{
					trace("Simulator reached worldTimeLimit");
					break;
				}
				// GC.disable();
				synchronized (Globals.simMut.writer)
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
					Globals.vessels.preKinematics();
					profiler.stopLast();
					profiler.start("acous.preKinematics");
					Globals.acous.preKinematics();
					profiler.stopLast();
					// physics integration. All rigid bodies are moved.
					profiler.start("phys.integratePBodies");
					Globals.phys.integratePBodies(1.0f, 0.25f);
					profiler.stopLast();
					m_worldTime += 1000_000;
					profiler.start("acous.postKinematics");
					Globals.acous.postKinematics(1.0f);
					profiler.stopLast();
					profiler.start("acous.processActiveSonars");
					Globals.acous.processActiveSonars();
					profiler.stopLast();
					profiler.start("acous.applySourcesOnHydrophones");
					Globals.acous.applySourcesOnHydrophones();
					profiler.stopLast();
					profiler.start("acous.postAcousticsUpdate");
					Globals.acous.postAcousticsUpdate();
					profiler.stopLast();
					profiler.start("weapons.updateGuidances");
					Globals.weapons.updateGuidances(1000_000);
					profiler.stopLast();
					profiler.start("vessels.postKinematics");
					Globals.vessels.postKinematics(1000_000);
					profiler.stopLast();
					profiler.start("animals.postKinematics");
					Globals.animals.postKinematics(1000_000);
					profiler.stopLast();
					profiler.start("vessels.collectDeadVessels");
					Globals.vessels.collectDeadVessels();
					profiler.stopLast();
					profiler.start("bots.onAfterSimulation");
					Globals.bots.onAfterSimulation();
					profiler.stopLast();
					if (Globals.scenario)
					{
						profiler.start("scenario.onAfterSimulation");
						Globals.scenario.onAfterSimulation();
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
				auto now = MonoTime.currTime();
				// GC.enable();
				loopStart = loopStart + msecs((1000 / acceleration).to!uint);
				now = MonoTime.currTime();
				Duration toSleep = loopStart - now;
				if (toSleep < msecs(100))
				{
					warning("simulator loop stalling");
					loopStart = now + msecs(100);
					toSleep = msecs(100);
				}
				if (doSleep)
					Thread.sleep(toSleep);
				else
				{
					loopStart = now;
					Thread.yield();
				}
			}
		}
		catch (Throwable t)
		{
			error("simulation thread has crashed: ", t.toString());
			exit(1);
		}
	}
}
