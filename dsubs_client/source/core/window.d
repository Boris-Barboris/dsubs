module dsubs_client.core.window;

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
			mode = sfVideoMode_getDesktopMode();
		ctx_settings.depthBits = 32;
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
		info("OK");
		// register default close handler
		register_handler(sfEvtClosed, &close_window);
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

private:
	sfRenderWindow* wnd;
	sfVideoMode mode;
	sfContextSettings ctx_settings;
	bool fullscreen = false;
	sfEventHandler[][sfEvtCount] event_handlers;

	void close_window(const sfEvent* evt)
	{
		info("Closing window");
		sfRenderWindow_close(wnd);
	}
}
