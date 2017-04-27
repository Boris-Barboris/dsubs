module dsubs_client.core.sfml;

import std.experimental.logger;

import derelict.sfml2.system;
import derelict.sfml2.window;
import derelict.sfml2.audio;
import derelict.sfml2.graphics;
import derelict.sfml2.network;


void loadSfmlLibraries()
{
    info("Loading CSFML dynamic libraries...");
    DerelictSFML2System.load();
    DerelictSFML2Window.load();
    DerelictSFML2Audio.load();
    DerelictSFML2Graphics.load();
    DerelictSFML2Network.load();
    info("OK");
}
