module dsubs_server.app;

import core.stdc.stdlib;

import dsubs_server.globals;


void main(string[] argv)
{
	scope(failure) exit(1);
	Globals.build();
	Globals.cons.bindSockets();
	Globals.sim.start();
	Globals.cons.startListeners();
	Globals.sim.join();		// blocks forever
	exit(0);
}