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
		usecs_t worldTime = 0;
		while (!stopRequested)
		{
			lastLoopStart = MonoTime.currTime();
			synchronized (g_simMut.writer)
			{
				// physics integration. All rigid bodies are moved.
				integratePBodies(0.25f, 0.25f);
				worldTime += 250_000;
				// need to send updated submarine coordinates to players
				forEachPlayer((pctx) { pctx.sendKinematicsUpdate(worldTime); });
			}
			auto now = MonoTime.currTime();
			Duration toSleep = msecs(250) - (now - lastLoopStart);
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