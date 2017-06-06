module dsubs_client.core.sfml;

import std.conv;
import std.experimental.logger;

import gfm.math.vector;
import gfm.math.matrix;

public import derelict.sfml2.system;
public import derelict.sfml2.window;
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

// event stuff

bool isMousePosEvent(const sfEvent* evt, out int x, out int y,
	out sfMouseButton mbutton, out int wheel_delta)
{
	if (evt.type == sfEvtMouseMoved)
	{
		x = evt.mouseMove.x;
		y = evt.mouseMove.y;
		mbutton = -1;
		wheel_delta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseButtonPressed)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheel_delta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseButtonReleased)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheel_delta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseWheelMoved)
	{
		x = evt.mouseWheel.x;
		y = evt.mouseWheel.y;
		mbutton = -1;
		wheel_delta = evt.mouseWheel.delta;
		return true;
	}
	return false;
}

bool isMousePosEvent(const sfEvent* evt)
{
	return (evt.type == sfEvtMouseMoved ||
			evt.type == sfEvtMouseButtonPressed ||
			evt.type == sfEvtMouseButtonReleased ||
			evt.type == sfEvtMouseWheelMoved);
}

bool isMouseEvent(const sfEvent* evt)
{
	return (isMousePosEvent(evt) ||
			isMouseEnterLeave(evt));
}

bool isMouseEnterLeave(const sfEvent* evt)
{
	return (evt.type == sfEvtMouseEntered ||
			evt.type == sfEvtMouseLeft);
}

bool isKeyboardEvent(const sfEvent* evt)
{
	return (evt.type == sfEvtTextEntered ||
			evt.type == sfEvtKeyPressed ||
			evt.type == sfEvtKeyReleased);
}

// conversions
sfVector2f tosf(const vec2f v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(const vec2ui v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(const vec2d v)
{
	return sfVector2f(to!float(v.x), to!float(v.y));
}

import std.meta;

sfTransform tosf(const ref mat3x3d m)
{
	sfTransform res;
	foreach (i; AliasSeq!(0, 1, 2, 6, 7, 8))
		res.matrix[i] = to!float(m.v[i]);
	// stupid screen-space sfml camera matrix with inverted Y
	foreach (j; AliasSeq!(3, 4, 5))
		res.matrix[j] = -to!float(m.v[j]);
	return res;
}
