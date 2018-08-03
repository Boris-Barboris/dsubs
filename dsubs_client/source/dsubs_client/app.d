module dsubs_client.app;

import core.stdc.stdlib;

import dsubs_client.common;
import dsubs_client.lib.sfml;
import dsubs_client.lib.openal;
import dsubs_client.lib.fonts;
import dsubs_client.tests;
import dsubs_client.game;


void main(string[] argv)
{
	version(unittest) info("Unit tests OK");
	version(linux)
	{
		initXLib();
	}
	loadSfmlLibraries();
	loadAudioLib();
	loadGlobalFonts();
	runModuleTests();
	//testGuiElements();
	scope(failure) exit(1);
	scope(failure) unloadAudioLib();
	try
	{
		Game.start();
		unloadAudioLib();
	}
	catch (Throwable t)
	{
		error(t.toString);
		throw t;
	}
	exit(0);
}
