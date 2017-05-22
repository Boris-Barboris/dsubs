module dsubs_client.render.render;

import core.thread;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_client.core.event;
public import dsubs_client.core.window;


// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Render ctx, Window wnd);
}

// TODO: move to config
sfColor clear_color = sfColor(28, 28, 28, 255);

/// Rendering context, renders one window.
class Render
{
	protected Window _window;
	IWindowDrawer gui_render;
	IWindowDrawer overlay_render;
	IWindowDrawer world_render;

	Window window() { return _window; }

	protected Thread worker;    // rendering thread
	protected bool stop_flag;	// true when stop was requested

	this(Window wnd)
	{
		_window = wnd;
		wnd.register_handler(sfEvtResized, &wnd_resized);
		wnd.register_handler(sfEvtClosed, (const sfEvent* a) { this.stop(); });
	}

	protected void wnd_resized(const sfEvent* evt)
	{
		sfView* view = sfView_createFromRect(
			sfFloatRect(0, 0, evt.size.width, evt.size.height));
		sfRenderWindow_setView(_window.ptr, view);
		sfView_destroy(view);
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
			worker.join();
	}

	// Thread function
	protected void render()
	{
		while (!stop_flag)
		{
			preRender(this);
			sfRenderWindow_clear(_window.ptr, clear_color);
			if (world_render)
				world_render.draw(this, _window);
			if (overlay_render)
				overlay_render.draw(this, _window);
			if (gui_render)
			{
				preGuiRender(this);
				gui_render.draw(this, _window);
			}
			postRender(this);
			sfRenderWindow_display(_window.ptr);		// present backbuffer
		}
		info("Terminating Render, stop_flag is ", stop_flag);
		worker = null;
	}

	Event!(void delegate(Render sender)) preRender;
	Event!(void delegate(Render sender)) postRender;
	Event!(void delegate(Render sender)) preGuiRender;
}
