module dsubs_client.world.manager;

import core.atomic;
import core.time;
import core.thread;
import core.sync.mutex;

import std.algorithm;
import std.experimental.logger;
import std.container : SList;
import std.range;

import dsubs_common.math.transform;

import dsubs_client.core.component;
import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.render.render;
import dsubs_client.world.camera;


/// Something that is rendered in world space.
/// Hierarchies are implemented using transform parenting.
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

	abstract void render(Window wnd, const mat3x3f mat);

	void update_transform() {}
}


/// Manages world-space objects rendering and IO event handling (selection).
class WorldManager: ComponentManager!"world", IWindowDrawer, IWindowEventHandler
{
	Camera2D[Window] cameras;

	// z-sorted array of component references
	WorldRenderable[] components = new WorldRenderable[](1024);
	// true component count
	private size_t comp_count = 0;

	this()
	{
		add_queue_mutex = new Object();
		remove_queue_mutex = new Object();
		// guaranteed transform update during next rendering
		last_update = MonoTime.currTime - target_frame_time;
	}

	// Components will be forced to update their transforms if this much
	// time has passed since the last update. Default duration implies
	// guaranteed recalculation if FPS is not larger than 200.
	Duration target_frame_time = dur!"msecs"(1000 / 200);

	// Moment of time the last transform update happenned.
	private MonoTime last_update;

	// number of threads currently rendering
	private shared int threads_rendering = 0;

	// when transform update is needed, thread that performs the update
	// sets this to true. When set to true, you need to block on entrance and
	// wait until it's true again
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
		{
			// wait until flag is false
			Thread.yield();
		}

		// critical section on time and transform update
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
				// next we force active components to update their transforms
				for (int i = 0; i < comp_count; i++)
				{
					auto comp = components[i];
					if (comp.active)
						comp.update_transform;
				}
				// and sort them in Z-order, deepest components first
				sort!((a, b) => a.depth < b.depth)(components[0 .. comp_count]);
				// register update
				last_update = cur_time;
				transform_sync = false;
			}
		}

		// rendering section
		atomicOp!"+="(threads_rendering, 1);
		// then we select the camera
		auto camera = cameras[wnd];
		mat3x3f camera_mat = camera.world2screen;
		// and render components on the window
		for (int i = 0; i < comp_count; i++)
		{
			auto comp = components[i];
			if (comp.active)
				comp.render(wnd, camera_mat);
		}
		atomicOp!"-="(threads_rendering, 1);
	}

	Object add_queue_mutex;
	SList!WorldRenderable add_queue;

	private void flush_add_requests()
	{
		synchronized(add_queue_mutex)
		{
			while (!add_queue.empty)
			{
				WorldRenderable obj = add_queue.front;
				_addRoot(obj);
				add_queue.removeFront();
			}
		}
	}

	private void _addRoot(WorldRenderable obj)
	{
		if (comp_count == components.length)
			components.length = comp_count * 2;
		components[comp_count++] = obj;
	}

	void addRoot(WorldRenderable obj)
	{
		synchronized (add_queue_mutex)
		{
			add_queue.insertFront(obj);
		}
	}

	Object remove_queue_mutex;
	SList!WorldRenderable remove_queue;

	private void flush_remove_requests()
	{
		synchronized(remove_queue_mutex)
		{
			while (!remove_queue.empty)
			{
				WorldRenderable obj = remove_queue.front;
				_removeRoot(obj);
				remove_queue.removeFront();
			}
		}
	}

	private void _removeRoot(WorldRenderable obj)
	{
		for (int i = 0; i < comp_count; i++)
		{
			if (obj is components[i])
			{
				for (int j = i; j < comp_count - 1; j++)
					components[j] = components[j + 1];
				components[comp_count - 1] = null;
				comp_count--;
				return;
			}
		}
	}

	void removeRoot(WorldRenderable obj)
	{
		synchronized (remove_queue_mutex)
		{
			remove_queue.insertFront(obj);
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
}
