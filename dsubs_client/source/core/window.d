module dsubs_client.core.window;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;

public import derelict.sfml2.graphics;
public import derelict.sfml2.window;


alias sfEventHandler = void delegate(const sfEvent*);

class Window
{
	this(dstring window_name = "dsubs")
	{
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
	}

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
		event_handlers[type] ~= handler;
	}

	void unregister_handler(sfEventType type, sfEventHandler handler)
	{
		event_handlers[type] = array(remove!(a => a == handler)(event_handlers[type]));
	}

	/// Function polls all events in window buffer and calls respective
	/// handlers, if registered.
	void poll_events()
	{
		sfEvent event;
		while (sfRenderWindow_pollEvent(wnd, &event))
		{
			sfEventHandler[] handlers = event_handlers[event.type];
			foreach (h; handlers)
				h(&event);
		}
	}

	void close_window()
	{
		info("Closing window");
		sfRenderWindow_close(wnd);
	}

	// Raw SFML window pointer
	sfRenderWindow* ptr() { return wnd; }

	uint width() const { return mode.width; }
	uint height() const { return mode.height; }

private:
	sfRenderWindow* wnd;
	sfVideoMode mode;
	sfContextSettings ctx_settings;
	bool fullscreen = false;
	sfEventHandler[][sfEvtCount] event_handlers;

	void resized_handler(const sfEvent* evt)
	{
		mode.width = evt.size.width;
		mode.height = evt.size.height;
		info("Resize event caught, ", width, "x", height);
	}
}
