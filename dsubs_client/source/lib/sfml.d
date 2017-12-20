module dsubs_client.lib.sfml;

import std.conv: to;
import std.experimental.logger: info;
import std.meta: AliasSeq;

import gfm.math.vector;
import gfm.math.matrix;

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

bool isMousePosEvent(in sfEvent* evt, out int x, out int y,
	out sfMouseButton mbutton, out int wheelDelta)
{
	if (evt.type == sfEvtMouseMoved)
	{
		x = evt.mouseMove.x;
		y = evt.mouseMove.y;
		mbutton = -1;
		wheelDelta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseButtonPressed)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheelDelta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseButtonReleased)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheelDelta = 0;
		return true;
	}
	if (evt.type == sfEvtMouseWheelMoved)
	{
		x = evt.mouseWheel.x;
		y = evt.mouseWheel.y;
		mbutton = -1;
		wheelDelta = evt.mouseWheel.delta;
		return true;
	}
	return false;
}

bool isMousePosEvent(in sfEvent* evt)
{
	return (evt.type == sfEvtMouseMoved ||
			evt.type == sfEvtMouseButtonPressed ||
			evt.type == sfEvtMouseButtonReleased ||
			evt.type == sfEvtMouseWheelMoved);
}

bool isMouseEvent(in sfEvent* evt)
{
	return (isMousePosEvent(evt) ||
			isMouseEnterLeave(evt));
}

bool isMouseEnterLeave(in sfEvent* evt)
{
	return (evt.type == sfEvtMouseEntered ||
			evt.type == sfEvtMouseLeft);
}

bool isKeyboardEvent(in sfEvent* evt)
{
	return (evt.type == sfEvtTextEntered ||
			evt.type == sfEvtKeyPressed ||
			evt.type == sfEvtKeyReleased);
}

// conversions
sfVector2f tosf(in vec2f v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(in vec2ui v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(in vec2i v)
{
	return sfVector2f(v.x, v.y);
}

sfIntRect tosf(in vec4i r)
{
	return sfIntRect(r[0], r[1], r[2], r[3]);
}

unittest
{
	vec4i v1 = vec4i(0, 1, 2, 3);
	sfIntRect v2 = tosf(v1);
	assert(v1.left == 0);
	assert(v1.top == 1);
	assert(v1.width == 2);
	assert(v1.height == 3);
}

sfVector2f tosf(in vec2d v)
{
	return sfVector2f(to!float(v.x), to!float(v.y));
}

// precision downscaling
sfTransform tosf(in mat3x3d m)
{
	sfTransform res;
	foreach (i; AliasSeq!(0, 1, 2, 6, 7, 8))
		res.matrix[i] = to!float(m.v[i]);
	// stupid screen-space sfml camera matrix with inverted Y
	foreach (j; AliasSeq!(3, 4, 5))
		res.matrix[j] = -to!float(m.v[j]);
	return res;
}
