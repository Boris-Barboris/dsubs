module dsubs_server.simulator;

import std.conv: to;
import std.datetime;
import std.math;

import core.atomic;
import core.thread;
import core.sync.mutex;
import core.sync.rwmutex;

import dsubs_common.api.constants;

import dsubs_server.common;
import dsubs_server.player;
import dsubs_server.dynamics;


/** mutex to guard game state. Player connections act as readers, they use
fine grained or no locking at all. Simulator is a writer. */
__gshared ReadWriteMutex g_simMut;

shared static this()
{
	g_simMut = new ReadWriteMutex();
}

private __gshared
{
	Thread simulThread;
	bool stopRequested = false;
	typeof(MonoTime.currTime) lastLoopStart;
}

/// start simulator thread
void startSimulator()
{
	assert(simulThread is null);
	stopRequested = false;
	simulThread = new Thread(&simulationLoop).start();
}

void stopSimulator()
{
	stopRequested = true;
	simulThread.join(false);
}

/// main loop
private void simulationLoop()
{
	try
	{
		int counter = 0;
		usecs_t worldTime = 0;
		while (!stopRequested)
		{
			synchronized (g_simMut.writer)
			{
				lastLoopStart = MonoTime.currTime();
				// physics integration. All rigid bodies are moved.
				integratePBodies(1.0f, 0.25f);
				worldTime += 1000_000;
				// need to send updated submarine coordinates to players
				forEachPlayer((pctx) { pctx.sendKinematicsUpdate(worldTime); });
			}
			auto now = MonoTime.currTime();
			trace("Simulation step took ", (now - lastLoopStart).total!"usecs", "usecs");
			counter = (counter + 1) % 10;
			Duration toSleep = seconds(1) - (now - lastLoopStart);
			if (toSleep < Duration.zero)
				toSleep = Duration.zero;
			Thread.sleep(toSleep);
		}
		info("Exiting simulation loop, stopRequested flag is set");
	}
	catch (Throwable t)
	{
		error("simulation thread has crashed: ", t.toString());
		throw t;
	}
}