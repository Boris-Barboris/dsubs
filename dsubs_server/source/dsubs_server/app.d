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
module dsubs_server.app;

import core.stdc.stdlib;
import core.thread;
import core.memory: GC;
import core.time: seconds, msecs;

import std.process: environment;

import dsubs_server.common;
import dsubs_server.connections.database;
import dsubs_server.connections.metrics;
import dsubs_server.globals;
import dsubs_server.scenario;
import dsubs_server.simulator;

version(Windows)
{
	extern(Windows) int SetConsoleOutputCP(uint);
	extern(C) __gshared string[] rt_options = [
		"gcopt=gc:precise cleanup:finalize", "scanDataSeg=precise" ];
}

version(Posix)
{
	extern(C) __gshared string[] rt_options = ["gcopt=gc:precise cleanup:finalize"];
}

void main(string[] argv)
{
	version(Windows)
	{
		SetConsoleOutputCP(65001);
	}
	try
	{
		string mysqlConStr = environment.get("MYSQL_CONSTRING");
		if (mysqlConStr)
		{
			info("initializing database connector");
			Globals.database = new DatabaseService(mysqlConStr);
		}
		string influxUrl = environment.get("INFLUXDB_URL");
		if (influxUrl)
		{
			info("initializing metrics connector");
			Globals.metrics = new MetricsService(influxUrl);
		}
		Globals.build();
		Globals.scenarioDb.startPeristentSimulators();
		Globals.cons.bindSockets();
		Globals.simulators.start();
		Globals.cons.startListeners();
		auto livenessThread = new Thread(&livenessWatchdog).start();
		auto playerPurgerThread = new Thread(&playerPeriodicPurger).start();
		auto gcThread = new Thread(&forcedGcThread).start();
		Globals.simulators.join();		// blocks forever
	}
	catch (Throwable e)
	{
		error("main thread has crashed: ", e.toString);
		exit(1);
	}
	exit(0);
}


/// Infinithe thread that watches main arena's time in a loop and
/// aborts the server process when it notices the deadlock or excessive stalling.
void livenessWatchdog()
{
	Simulator mainArenaSim = Globals.scenarioDb.getPersistentById("main_arena").simulator;
	usecs_t lastWorldTime = mainArenaSim.worldTime;
	string lastUniqId = mainArenaSim.uniqId;
	while (true)
	{
		Thread.sleep(seconds(14));
		mainArenaSim = Globals.scenarioDb.getPersistentById("main_arena").simulator;
		if (mainArenaSim.worldTime == lastWorldTime && lastUniqId == mainArenaSim.uniqId)
		{
			error("ABORTING process, liveness failure of main arena");
			abort();
		}
		lastWorldTime = mainArenaSim.worldTime;
		lastUniqId = mainArenaSim.uniqId;
	}
}

void forcedGcThread()
{
	while (true)
	{
		Thread.sleep(minutes(31));
		GC.collect();
		GC.minimize();
	}
}

void playerPeriodicPurger()
{
	while(true)
	{
		Thread.sleep(minutes(6));
		Globals.players.purgeDanglingPlayers();
	}
}