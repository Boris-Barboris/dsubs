module dsubs_client.render.render;

import core.time;
import core.thread;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_client.core.event;
public import dsubs_client.core.window;
import module dsubs_client.input.router: Router;


// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Render ctx, Window wnd);
}

// TODO: move to config
sfColor clear_color = sfColor(28, 28, 28, 255);

/// Rendering thread wrapper, renders one window and dictates general form
/// of the rendering pipeline.
final class Render
{
	private Window _window;
	private Router _router;
	IWindowDrawer gui_render;
	IWindowDrawer overlay_render;
	IWindowDrawer world_render;

	@property Window window() const { return _window; }
	@property Router router() const { return _router; }

	private Thread worker;    // rendering thread
	private bool stop_flag;	// true when stop was requested

	this(Window wnd, Router router)
	{
		_window = wnd;
		_router = router;
		wnd.register_handler(sfEvtClosed, (const sfEvent* a) { this.stop(); });
	}

	void start()
	{
		if (worker)
			throw new Exception("Render already started");
		info("Deactivating window GL context in parent thread...");
		sfRenderWindow_setActive(_window.ptr, false);
		info("OK");
		info("Starting render thread...");
		worker = new Thread(&render).start();
		info("OK");
	}

	void stop_async() { stop_flag = true; }

	// blocking stop
	void stop()
	{
		stop_flag = true;
		if (worker)
			worker.join(false);
	}

	// Thread function
	private void render()
	{
		try
		{
			while (!stop_flag)
			{
				sfRenderWindow_clear(_window.ptr, clear_color);
				_window.input_mutex.lock();		// take the window lock
				{
					scope(exit) _window.input_mutex.unlock();
					if (world_render)
						world_render.draw(this, _window);
					if (overlay_render)
						overlay_render.draw(this, _window);
					_router.simulate_mouse_move();
					if (gui_render)
						gui_render.draw(this, _window);
				}	// here window input_mutex is unlocked
				// present backbuffer, blocks because of vsync.
				sfRenderWindow_display(_window.ptr);
			}
		}
		catch (Error err)
		{
			error("Render loop crashed with error: ", err.toString);
			throw err;
		}
		info("Terminating Render, stop_flag is ", stop_flag);
	}
}
