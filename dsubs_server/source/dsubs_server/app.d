module dsubs_server.app;

import dsubs_server.globals;

int main(string[] argv)
{
	Globals.build();
	Globals.cons.bindSockets();
	Globals.sim.start();
	Globals.cons.startListeners();
	Globals.sim.join();		// blocks forever
	return 0;
}