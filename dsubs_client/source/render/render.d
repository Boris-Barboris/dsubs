module dsubs_client.render.render;

import core.thread;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

public import dsubs_client.core.window;


// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Render ctx, Window wnd);
}

// move to config
sfColor clear_color = sfColor(24, 24, 24, 255);

/// Rendering context, renders one window.
class Render
{
	Window window;
	IWindowDrawer gui_render;
	IWindowDrawer overlay_render;
	IWindowDrawer world_render;

	protected Thread worker;    // rendering thread
	protected bool stop_flag;	// true when stop was requested

	this(Window wnd)
	{
		window = wnd;
	}

	void start()
	{
		if (worker)
			throw new Exception("Render already started");
		info("Deactivating window GL context in parent thread...");
		sfRenderWindow_setActive(window.ptr, false);
		info("OK");
		info("Starting render...");
		worker = new Thread(&render).start();
		info("OK");
	}

	void stop_async() { stop_flag = true; }

	// blocking stop
	void stop()
	{
		stop_flag = true;
		worker.join();
	}

	// Thread function
	protected void render()
	{
		while (!stop_flag)
		{
			sfRenderWindow_clear(window.ptr, clear_color);
			if (world_render)
				world_render.draw(this, window);
			if (overlay_render)
				overlay_render.draw(this, window);
			if (gui_render)
				gui_render.draw(this, window);
			sfRenderWindow_display(window.ptr);		// present backbuffer
		}
		info("Terminating Render, stop_flag is ", stop_flag);
		worker = null;
	}
}
