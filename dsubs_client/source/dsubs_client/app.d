module dsubs_client.app;

import std.experimental.logger;

import dsubs_client.lib.sfml;
import dsubs_client.lib.fonts;
import dsubs_client.tests;

import dsubs_client.game;


int main(string[] argv)
{
	version ( unittest ) info("Unit tests OK");
	loadSfmlLibraries();
	loadGlobalFonts();
	runModuleTests();
	//testGuiElements();
	Game.start();
	return 0;
}
