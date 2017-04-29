module dsubs_client.core.sfml;

import std.experimental.logger;

import gfm.math.vector;

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


// utility conversions
sfVector2f tosf(vec2d v) { return sfVector2f(v.x, v.y); }
sfVector2f tosf(vec2f v) { return sfVector2f(v.x, v.y); }
