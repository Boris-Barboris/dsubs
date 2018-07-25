module dsubs_client.app;

import core.stdc.stdlib;

import dsubs_client.common;
import dsubs_client.lib.sfml;
import dsubs_client.lib.fonts;
import dsubs_client.tests;
import dsubs_client.game;

version(linux)
{
	import core.stdc.signal;
	extern(C) void handleSegv(int) nothrow @nogc { assert(0); }
}

void main(string[] argv)
{
	version(unittest) info("Unit tests OK");
	version(linux)
	{
		initXLib();
		signal(SIGSEGV, &handleSegv);
	}
	loadSfmlLibraries();
	loadGlobalFonts();
	runModuleTests();
	//testGuiElements();
	Game.start();
	exit(0);
}
