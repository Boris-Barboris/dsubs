module dsubs_client.render.worldmanager;

import core.atomic;
import core.time;
import core.thread;
import core.sync.mutex;

import std.algorithm;
import std.experimental.logger;
import std.range;

import derelict.sfml2.graphics;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.math.transform;
import dsubs_client.render.render;
import dsubs_client.render.camera;


/// Something that is rendered in world space.
/// Reference frame hierarchies are implemented using transform parenting.
class WorldRenderable
{
	mixin Readonly!(Transform, "transform");

	/// yes, we're actually 2.5D
	float depth = 0.0f;

	this()
	{
		m_transform = new Transform();
	}

	/// Generally, it may well be some texture instead of window
	abstract void render(Window wnd);

	/** View is not a model. Component transform is not bound to objects real
	(server-side) position and may be inter\extrapolated on arbitrary refresh rate.
	To create an illusion of smoothness, game objects will update their transforms
	every frame. After update, all renderables will be rendered by all interested
	cameras. */
	void update(CameraContext camCtx, long usecsDelta) {}
}

/// Wrapper around camera
final class CameraContext
{
	Camera2D camera;

	// TODO: here is the place for some spacial optimization structures that are
	// related to the camera itself

	// window or any other renderable
	this(scope Window wnd)
	{
		camera = new Camera2D(vec2ui(wnd.width, wnd.height));
	}
}


/// Something that may receive mouse events in the context of world space
interface WorldMouseReceiver: IInputReciever
{
	bool isMouseEventInteresting(Window wnd, const sfEvent* evt, int x, int y);
}


/// Manages world-space objects rendering and IO event handling
/// (selection, picking).
final class WorldManager: IWindowDrawer, IWindowEventSubrouter
{
	// Let's say we always have one camera spanning whole window.
	CameraContext camCtx;

	/// everything that will be rendered in draw call
	WorldRenderable[] components;

	void clear()
	{
		components.length = 0;
		mouseReceivers.length = 0;
	}

	this(Window wnd)
	{
		camCtx = new CameraContext(wnd);
		components.reserve(512);
	}

	void draw(Window wnd, long usecsDelta)
	{
		// TODO: maybe spread load on a thread pool
		foreach (comp; components)
			comp.update(camCtx, usecsDelta);
		// and sort them in Z-order, deepest components first
		// sort!((a, b) => a.depth < b.depth)(components[]);
		// apply camera transformation
		sfRenderWindow_setView(wnd.wnd, camCtx.camera.view);
		// render components on the window
		foreach (comp; components)
			comp.render(wnd);
	}

	unittest
	{
		int[5] arr = [3, 2, 1, 2, 2];
		sort(arr[0 .. 3]);
		assert(arr == [1, 2, 3, 2, 2]);
		assert(arr != [1, 2, 2, 3, 2]);
		assert(arr != [1, 2, 2, 2, 3]);
	}

	// Event handling

	/// objects that may receive mouse right after renderables
	WorldMouseReceiver[] mouseReceivers;

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		foreach (mr; mouseReceivers)
		{
			if (mr.isMouseEventInteresting(wnd, evt, x, y))
				return RouteResult(mr);
		}
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt)
	{
		camCtx.camera.screenSize = vec2ui(evt.width, evt.height);
	}
}
