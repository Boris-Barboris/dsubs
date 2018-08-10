module dsubs_server.simulator;

import std.datetime;

import core.thread;
import core.memory;
import core.stdc.stdlib;

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
			MonoTime simStart;
			while (true)
			{
				synchronized (Globals.simMut.writer)
				{
					GC.disable();
					simStart = MonoTime.currTime();
					Globals.acous.preSimulation();
					// physics integration. All rigid bodies are moved.
					Globals.phys.integratePBodies(1.0f, 0.25f);
					Globals.acous.postSimulation(1.0f);
					Globals.acous.applySourcesOnHydrophones();
					m_worldTime += 1000_000;
					// stream updates to players
					Globals.players.forEachPlayer((p) { p.sendUpdate(); });
				}
				auto now = MonoTime.currTime();
				GC.enable();
				trace("Simulation step took ", (now - simStart).total!"usecs", "usecs");
				loopStart = loopStart + seconds(1);
				now = MonoTime.currTime();
				Duration toSleep = loopStart - now;
				if (toSleep < Duration.zero)
				{
					error("simulator stalling");
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