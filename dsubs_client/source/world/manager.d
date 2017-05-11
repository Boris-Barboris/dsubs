module dsubs_client.world.manager;

import core.atomic;
import core.time;
import core.thread;
import core.sync.mutex;

import std.algorithm;
import std.experimental.logger;
import std.container.array;
import std.range;

import dsubs_common.math.transform;

import dsubs_client.core.component;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.render.render;
import dsubs_client.world.camera;


/// Something that is rendered in world space.
/// Hierarchies and connections are implemented using transform parenting.
class WorldRenderable: Component!"world"
{
	Transform2D transform;
	double depth;		// yes, we're actually 2.5D

	this (WorldManager manager)
	{
		super(manager);
		transform = new Transform2D();
		depth = 0.0;
	}

	abstract void render(Window wnd, const(mat3x3d)* mat);

	// View is not model. Component transform is not bound to objects real
	// position and may be inter\extrapolated on different refresh rate.
	// When the frame is rendered, this method is called by that window's
	// thread in order to update object's transform.
	void update_transform() {}
}


/// Manages world-space objects rendering and IO event handling
/// (selection, picking).
class WorldManager: ComponentManager!"world", IWindowDrawer, IWindowEventHandler
{
	// Let's say we always have one camera spanning whole window.
	Camera2D[Window] cameras;

	// z-sorted array of component references
	Array!WorldRenderable components;

	this()
	{
		components.reserve(256);
		add_queue_mutex = new Object();
		remove_queue_mutex = new Object();
		// guaranteed transform update during next rendering
		last_update = MonoTime.currTime - target_frame_time;
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
	void draw(Render ctx, Window wnd)
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
				// wait until no threads are drawing
				while (threads_rendering > 0)
					Thread.yield();
				// update component list itself
				flush_add_requests();
				flush_remove_requests();
				// force active components to update their transforms
				foreach (WorldRenderable comp; components)
					if (comp.active)
						comp.update_transform();
				// and sort them in Z-order, deepest components first
				sort!((a, b) => a.depth < b.depth)(components[]);
				// register update
				last_update = cur_time;
				transform_sync = false;
			}
		}

		// rendering section
		atomicOp!"+="(threads_rendering, 1);
		// then we select the camera
		auto camera = cameras[wnd];
		mat3x3d camera_mat = camera.world2screen;
		// and render components on the window
		foreach (WorldRenderable comp; components)
			if (comp.active)
				comp.render(wnd, &camera_mat);
		atomicOp!"-="(threads_rendering, 1);
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

	override void clear_disposed()
	{
		throw new Exception("not implemented yet");
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

	HandleResult handleEvent(Router ctx, const sfEvent* evt)
	{
		throw new Exception("not implemented yet");
	}
}
