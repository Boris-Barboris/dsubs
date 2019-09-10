module dsubs_server.app;

import core.stdc.stdlib;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.scenario;

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
		Globals.build();
		Globals.scenario = new BattleRoyale();
		Globals.cons.bindSockets();
		Globals.sim.start();
		Globals.cons.startListeners();
		Globals.sim.join();		// blocks forever
	}
	catch (Throwable e)
	{
		error("main thread has crashed: ", e.toString);
		exit(1);
	}
	exit(0);
}