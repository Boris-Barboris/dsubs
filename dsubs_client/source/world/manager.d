module dsubs_client.world.manager;

import core.atomic;
import core.time;
import core.thread;
import core.sync.mutex;

import std.algorithm;
import std.experimental.logger;
import std.container.array;
import std.range;

import derelict.sfml2.graphics;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.math.transform;
import dsubs_client.render.render;
import dsubs_client.world.camera;


/// Something that is rendered in world space.
/// Reference frame hierarchies are implemented using transform parenting.
class WorldRenderable
{
	private Transform m_transform;
	@property Transform transform() { return m_transform; }

	/// yes, we're actually 2.5D
	double depth;

	this()
	{
		m_transform = new Transform();
		depth = 0.0;
	}

	/// Generally, it may well be some texture instead of window
	abstract void render(Window wnd);

	/** View is not model. Component transform is not bound to objects real
	position and may be inter\extrapolated on different refresh rate.
	When the frame is rendered, this method is called by that window's
	thread in order to update object's transform. */
	void updateTransform() {}
}

class CameraContext
{
	Camera2D camera;
	mat3x3d world2screen;
	mat3x3d screen2world;

	// window or any other renderable
	this(Window wnd)
	{
		camera = new Camera2D(vec2ui(wnd.width, wnd.height));
		update();
	}

	void update()
	{
		world2screen = camera.world2screen;
		screen2world = camera.screen2world;
	}
}

/// Manages world-space objects rendering and IO event handling
/// (selection, picking).
class WorldManager: IWindowDrawer, IWindowEventSubrouter
{
	// Let's say we always have one camera spanning whole window.
	CameraContext[Window] cameras;

	CameraContext generate_context(Window wnd)
	{
		CameraContext ctx = new CameraContext(wnd);
		cameras[wnd] = ctx;
		return ctx;
	}

	// z-sorted array of component references
	Array!WorldRenderable components;

	this()
	{
		components.reserve(512);
		add_queue_mutex = new Object();
		remove_queue_mutex = new Object();
		// guaranteed transform update during next rendering
		last_update = MonoTime.currTime;
	}

	// Components will be forced to update their transforms if this much
	// time has passed since the last update. Default duration implies
	// guaranteed recalculation each frame if FPS is not greater than 200.
	Duration target_frame_time = dur!"msecs"(1000 / 200);

	// Moment of time the last transform update happenned
	private MonoTime last_update;

	// number of threads currently rendering
	private shared int threads_rendering = 0;

	// when transform update is needed, thread that performs the update
	// sets this to true. When set to true, you need to block on entrance to
	// rendering block and wait until it's false again
	private shared bool transform_sync = false;

	// There may be multimple windows requesting rendering simultaneously.
	// Rendering consists of issuing opengl commands in the form of
	// pushing transforms of objects to driver stack. There is no need
	// to update object transforms more frequently, that rendering is
	// requested. There is also no need to update transforms between two
	// very close rendering calls, issued by different windows.
	void draw(Window wnd)
	{
		while (transform_sync)
			Thread.yield();

		synchronized (this)
		{
			MonoTime cur_time = MonoTime.currTime;
			if (cur_time - last_update >= target_frame_time)
			{
				// enough time has passed since last transform update to
				// justify transform recalculations
				transform_sync = true;
				scope(exit) transform_sync = false;
				// wait until no threads are drawing
				while (threads_rendering > 0)
					Thread.yield();
				// update component list itself
				flush_add_requests();
				flush_remove_requests();
				// force active components to update their transforms
				// TODO: spread load on thread pool
				foreach (WorldRenderable comp; components)
					comp.updateTransform();
				// and sort them in Z-order, deepest components first
				sort!((a, b) => a.depth < b.depth)(components[]);
				// register update
				last_update = cur_time;
			}
		}

		// rendering section
		atomicOp!"+="(threads_rendering, 1);
		scope(exit) atomicOp!"-="(threads_rendering, 1);
		// then we select the camera
		CameraContext camctx = cameras[wnd];
		camctx.update();
		sfRenderWindow_setView(wnd.wnd, camctx.camera.view);
		// and render components on the window
		foreach (WorldRenderable comp; components)
			comp.render(wnd);
		// return default view to the window
		sfRenderWindow_setView(wnd.wnd, wnd.view);
	}

	Object add_queue_mutex;
	Array!WorldRenderable add_queue;

	private void flush_add_requests()
	{
		synchronized(add_queue_mutex)
		{
			foreach (WorldRenderable obj; add_queue)
				components.insertBack(obj);
			add_queue.clear();
		}
	}

	void addRoot(WorldRenderable obj)
	{
		synchronized (add_queue_mutex)
		{
			add_queue.insertBack(obj);
		}
	}

	Object remove_queue_mutex;
	Array!WorldRenderable remove_queue;

	private void flush_remove_requests()
	{
		synchronized(remove_queue_mutex)
		{
			components.substract(remove_queue[]);
			remove_queue.clear();
		}
	}

	void removeRoot(WorldRenderable obj)
	{
		synchronized (remove_queue_mutex)
		{
			remove_queue.insertBack(obj);
		}
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

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt)
	{
		// we need to resize camera
		CameraContext* camctx = wnd in cameras;
		if (camctx)
			camctx.camera.screenSize = vec2ui(evt.width, evt.height);
	}
}
