module dsubs_client.core.window;

import core.sync.mutex;
import core.stdc.stdlib: free;

import std.algorithm;
import std.array;
import std.string: toStringz;
import std.conv: to;
import std.experimental.logger: info, trace;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
public import derelict.sfml2.window;

import dsubs_common.event;


alias sfEventHandler = void delegate(Window, const sfEvent*);

/// wrapper around sfml window
final class Window
{
	this(dstring windowName = "dsubs"d)
	{
		m_mode = sfVideoMode_getDesktopMode();
		info("DesktopMode: ", m_mode);
		m_mode.width = 640; // to!uint(m_mode.width / 1.4);
		m_mode.height = 480; // to!uint(m_mode.height / 1.4);
		m_ctxSettings.depthBits = 24;
		m_ctxSettings.stencilBits = 8;
		m_ctxSettings.antialiasingLevel = 4;
		m_ctxSettings.majorVersion = 3;
		m_ctxSettings.minorVersion = 2;
		m_ctxSettings.attributeFlags = sfContextDefault;
		m_ctxSettings.sRgbCapable = false;
		info("OpenGL context settings: ", m_ctxSettings);
		info("Creating window...");
		m_wnd = sfRenderWindow_createUnicode(m_mode, windowName.ptr,
											sfDefaultStyle, &m_ctxSettings);
		sfRenderWindow_setVerticalSyncEnabled(m_wnd, true);
		info("OK");
		// register default handlers
		registerHandler(sfEvtResized, &resizedHandler);
		m_view = sfView_create();
		// custom sfml patch enables scissor testing
		sfRenderWindow_setScissorTest(m_wnd, true);
		resetView();
	}

	@property void title(string rhs)
	{
		// randomly deadlocks on Windows
		version(linux)
		{
			sfRenderWindow_setTitle(m_wnd, rhs.toStringz);
		}
	}

	// TODO: descructor

	private static const(sfVideoMode)[] getSupportedModes()
	{
		size_t mode_count = 0;
		auto modes = sfVideoMode_getFullscreenModes(&mode_count);
		return modes[0 .. mode_count];
	}

	private static sfVideoMode chooseBiggestMode()
	{
		auto modes = getSupportedModes();
		foreach (m; modes)
			info("Video mode detected: ", m);
		sfVideoMode res = modes[$-1];
		info("Selecting ", res);
		// free(cast(void*)modes.ptr);		// this may crash
		return res;
	}

	void registerHandler(sfEventType type, sfEventHandler handler)
	{
		m_eventHandlers[type] += handler;
	}

	void unregisterHandler(sfEventType type, sfEventHandler handler)
	{
		m_eventHandlers[type] -= handler;
	}

	private bool m_stopFlag = false;

	/// Call this in order to request pollEvents loop exit
	void stopEventProcessing()
	{
		m_stopFlag = true;
	}

	/// Function repeatedly polls events in window buffer and calls
	/// respective handlers, if registered. Blocks until the window is closed, or
	/// waitEvent returns error.
	void pollEvents(scope Mutex mutex)
	{
		sfEvent event;
		while (!m_stopFlag && sfRenderWindow_waitEvent(m_wnd, &event))
		{
			synchronized(mutex)
			{
				m_eventHandlers[event.type](this, &event);
				if (event.type == sfEvtClosed)
				{
					// actually close the window
					info("Standard window close event caught");
					m_stopFlag = true;
				}
			}
		}
	}

	/// Call this after exiting possEvents loop in order to destroy window handle
	void close()
	{
		info("closing window...");
		sfRenderWindow_close(m_wnd);
		m_wnd = null;
		info("OK");
	}

	/// Raw SFML window pointer
	@property sfRenderWindow* wnd() { return m_wnd; }

	@property sfView* view() { return m_view; }

	/// client area width
	@property uint width() const { return m_mode.width; }

	/// client area height
	@property uint height() const { return m_mode.height; }

	@property bool hasFocus() const { return sfRenderWindow_hasFocus(m_wnd) == sfTrue; }

	// reset view and scissors to window size
	void resetView()
	{
		sfView_reset(m_view, sfFloatRect(0.0f, 0.0f, m_mode.width, m_mode.height));
		sfRenderWindow_setScissor(m_wnd, sfIntRect(0, 0, m_mode.width, m_mode.height));
		sfRenderWindow_setView(m_wnd, m_view);
	}

private:
	sfRenderWindow* m_wnd;
	sfView* m_view;
	sfVideoMode m_mode;
	sfContextSettings m_ctxSettings;
	Event!(void delegate(Window wnd, const sfEvent* evt))[sfEvtCount] m_eventHandlers;

	void resizedHandler(Window wnd, const sfEvent* evt)
	{
		m_mode.width = evt.size.width;
		m_mode.height = evt.size.height;
		trace("Resize event caught, w=", width, " h=", height);
	}
}
