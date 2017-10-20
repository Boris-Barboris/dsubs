module dsubs_client.core.window;

import core.sync.mutex;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;

public import derelict.sfml2.graphics;
public import derelict.sfml2.window;

import dsubs_client.core.event;


alias sfEventHandler = void delegate(const sfEvent*);

final class Window
{
	this(dstring window_name = "dsubs"d)
	{
		gui_mutex = new Mutex();
		if (fullscreen)
			mode = chooseBiggestMode();
		else
		{
			mode = sfVideoMode_getDesktopMode();
			mode.width = to!uint(mode.width / 1.5);
			mode.height = to!uint(mode.height / 1.5);
		}
		ctx_settings.depthBits = 24;
		ctx_settings.stencilBits = 8;
		ctx_settings.antialiasingLevel = 4;
		ctx_settings.majorVersion = 3;
		ctx_settings.minorVersion = 2;
		ctx_settings.attributeFlags = sfContextDefault;
		info("OpenGL context settings: ", ctx_settings);
		info("Creating window...");
		wnd = sfRenderWindow_createUnicode(mode, window_name.ptr,
										   sfDefaultStyle, &ctx_settings);
		sfRenderWindow_setVerticalSyncEnabled(wnd, true);
		info("OK");
		// register default handlers
		register_handler(sfEvtResized, &resized_handler);
		_view = sfView_create();
		sfView_reset(_view, sfFloatRect(0.0, 0.0, width, height));
		sfRenderWindow_setView(wnd, _view);
		// custom sfml patch enables scissor testing
		sfRenderWindow_setScissorTest(wnd, true);
	}

	// this function is probably generating garbage, but i don't really care
	static const(sfVideoMode)[] getSupportedModes()
	{
		size_t mode_count = 0;
		auto modes = sfVideoMode_getFullscreenModes(&mode_count);
		return modes[0 .. mode_count];
	}

	static sfVideoMode chooseBiggestMode()
	{
		auto modes = getSupportedModes();
		foreach (m; modes)
			info("Video mode detected: ", m);
		info("Selecting ", modes[$-1]);
		sfVideoMode res = modes[$-1];
		return res;
	}

	void register_handler(sfEventType type, sfEventHandler handler)
	{
		event_handlers[type] += handler;
	}

	void unregister_handler(sfEventType type, sfEventHandler handler)
	{
		event_handlers[type] -= handler;
	}

	/// Function repeatedly polls all events in window buffer and calls
	/// respective handlers, if registered. Blocks until the window is closed.
	void poll_events()
	{
		bool closing = false;
		sfEvent event;
		while (sfRenderWindow_waitEvent(wnd, &event))
		{
			// special case: window close event
			if (event.type == sfEvtClosed)
			{
				event_handlers[event.type](&event);
				// actually close the window
				info("Standard window close event caught");
				sfRenderWindow_close(wnd);
				closing = true;
			}
			else
			{
				// we do not route events during rendering dispatch
				input_mutex.lock();
				scope(exit) imput_mutex.unlock();
				event_handlers[event.type](&event);
			}
			if (closing)
				break;
		}
	}

	void close_window()
	{
		info("Closing window");
		// Generate artificial close event
		sfEvent close_event;
		close_event.type = sfEvtClosed;
		event_handlers[sfEvtClosed](&close_event);
		// actually close the window
		sfRenderWindow_close(wnd);
		closing = true;
	}

	// Raw SFML window pointer
	sfRenderWindow* ptr() const { return wnd; }

	uint width() const { return mode.width; }
	uint height() const { return mode.height; }
	int hasFocus() const {	return sfRenderWindow_hasFocus(wnd); }

	// default window view will always be here
	sfView* view() { return _view; }

	// different usefull mutexes
	Mutex input_mutex;

private:
	sfRenderWindow* wnd;
	sfView* _view;
	sfVideoMode mode;
	sfContextSettings ctx_settings;
	bool fullscreen = false;
	Event!(const sfEvent*)[sfEvtCount] event_handlers;

	void resized_handler(const sfEvent* evt)
	{
		mode.width = evt.size.width;
		mode.height = evt.size.height;
		trace("Resize event caught, ", width, "x", height);
		// reset view
		sfView_reset(_view, sfFloatRect(0.0, 0.0, mode.width, mode.height));
		sfRenderWindow_setScissor(wnd, sfIntRect(0, 0, mode.width, mode.height));
		sfRenderWindow_setView(wnd, _view);
	}
}
