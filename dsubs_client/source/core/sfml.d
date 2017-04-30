module dsubs_client.core.sfml;

import std.conv;
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


// conversions
auto ref sfVector2f tosf(ref vec2f v)
{
	return *(cast(sfVector2f*)(&v));
}

sfVector2f tosf(const vec2d v)
{
	return sfVector2f(to!float(v.x), to!float(v.y));
}
