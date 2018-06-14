module dsubs_server.simulator;

import std.datetime;

import core.thread;

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

	private void simulationLoop()
	{
		try
		{
			usecs_t worldTime = 0;
			MonoTime lastLoopStart;
			while (true)
			{
				synchronized (Globals.simMut.writer)
				{
					lastLoopStart = MonoTime.currTime();
					// physics integration. All rigid bodies are moved.
					Globals.phys.integratePBodies(1.0f, 0.25f);
					worldTime += 1000_000;
					// need to send updated submarine coordinates to players
					Globals.players.forEachPlayer((p) { p.sendKinematicsUpdate(worldTime); });
				}
				auto now = MonoTime.currTime();
				trace("Simulation step took ", (now - lastLoopStart).total!"usecs", "usecs");
				Duration toSleep = seconds(1) - (MonoTime.currTime() - lastLoopStart);
				if (toSleep < Duration.zero)
					toSleep = Duration.zero;
				Thread.sleep(toSleep);
			}
		}
		catch (Throwable t)
		{
			error("simulation thread has crashed: ", t.toString());
			throw t;
		}
	}
}