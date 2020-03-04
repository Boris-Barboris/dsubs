module dsubs_server.app;

import core.stdc.stdlib;
import core.thread;
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

__gshared Simulator mainArenaSim;

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
		mainArenaSim = new Simulator("main_arena");
		auto scenario = new BattleRoyale(mainArenaSim);
		Globals.cons.bindSockets();
		Globals.simulators.add(mainArenaSim);
		Globals.simulators.start();
		Globals.cons.startListeners();
		auto livenessThread = new Thread(&livenessWatchdog).start();
		Globals.simulators.join();		// blocks forever
	}
	catch (Throwable e)
	{
		error("main thread has crashed: ", e.toString);
		exit(1);
	}
	exit(0);
}

void livenessWatchdog()
{
	usecs_t lastWorldTime = mainArenaSim.worldTime;
	while (true)
	{
		Thread.sleep(seconds(10));
		if (mainArenaSim.worldTime == lastWorldTime)
			abort();
		lastWorldTime = mainArenaSim.worldTime;
	}
}