module dsubs_server.simulator;

import std.datetime;

import core.thread;
import core.memory;
import core.stdc.stdlib;

import dsubs_common.proftimer;
import dsubs_server.common;
import dsubs_server.dynamics;


/// Simulation thread wrapper
final class Simulator
{
	private Thread m_thread;

	this()
	{
		m_thread = new Thread(&simulationLoop);
	}

	void start()
	{
		m_thread.start();
	}

	void join()
	{
		m_thread.join();
	}

	private usecs_t m_worldTime = 0;
	@property usecs_t worldTime() const { return m_worldTime; }

	private void simulationLoop()
	{
		try
		{
			MonoTime loopStart = MonoTime.currTime();
			ProfTimer profiler = new ProfTimer();
			while (true)
			{
				// GC.disable();
				synchronized (Globals.simMut.writer)
				{
					profiler.start();
					profiler.start("acous.preSimulation");
					Globals.acous.preSimulation();
					profiler.stopLast();
					// physics integration. All rigid bodies are moved.
					profiler.start("phys.integratePBodies");
					Globals.phys.integratePBodies(1.0f, 0.25f);
					profiler.stopLast();
					profiler.start("acous.postSimulation");
					Globals.acous.postSimulation(1.0f);
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
					m_worldTime += 1000_000;
					// stream updates to players
					profiler.start("players.forEachPlayer.sendUpdate");
					Globals.players.forEachPlayer((p) { p.sendUpdate(); });
					profiler.stopLast();
				}
				profiler.stop();
				profiler.printResult();
				auto now = MonoTime.currTime();
				// GC.enable();
				loopStart = loopStart + seconds(1);
				now = MonoTime.currTime();
				Duration toSleep = loopStart - now;
				if (toSleep < msecs(100))
				{
					warning("simulator loop stalling");
					loopStart = now + msecs(100);
					toSleep = msecs(100);
				}
				Thread.sleep(toSleep);
			}
		}
		catch (Throwable t)
		{
			error("simulation thread has crashed: ", t.toString());
			exit(1);
		}
	}
}