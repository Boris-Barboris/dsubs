module dsubs_client.app;

import core.stdc.stdlib;

import dsubs_client.common;
import dsubs_client.lib.sfml;
import dsubs_client.lib.openal;
import dsubs_client.lib.fonts;
import dsubs_client.tests;
import dsubs_client.game;

version(Windows)
{
	extern(Windows) int SetConsoleOutputCP(uint);
	extern(C) __gshared string[] rt_options = [ "gcopt=gc:precise", "scanDataSeg=precise" ];
}

void main(string[] argv)
{
	version(Windows)
	{
		SetConsoleOutputCP(65001);
	}
	version(unittest) info("Unit tests OK");
	version(linux)
	{
		initXLib();
	}
	loadSfmlLibraries();
	loadAudioLib();
	loadGlobalFonts();
	// runModuleTests();
	// testGuiElements();
	scope(exit) unloadAudioLib();
	try
	{
		Game.start();
	}
	catch (Throwable t)
	{
		error(t.toString);
		throw t;
	}
}
