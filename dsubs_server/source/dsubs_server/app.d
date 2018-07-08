module dsubs_server.app;

import dsubs_server.globals;
import dsubs_server.sound.wav;

int main(string[] argv)
{
	writeWhiteNoise();
	return 0;
	// Globals.build();
	// Globals.cons.bindSockets();
	// Globals.sim.start();
	// Globals.cons.startListeners();
	// Globals.sim.join();		// blocks forever
	// return 0;
}