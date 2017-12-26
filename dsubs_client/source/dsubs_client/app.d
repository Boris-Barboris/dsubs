module dsubs_client.app;

import std.experimental.logger;

import dsubs_client.lib.sfml;
import dsubs_client.lib.fonts;
import dsubs_client.tests;


int main(string[] argv)
{
	info("Unit tests OK");
	loadSfmlLibraries();
	loadGlobalFonts();
	runModuleTests();
	testGuiElements();
	return 0;
}
