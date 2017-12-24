module dsubs_client.render.render;

import core.time;
import core.thread;
import core.sync.mutex;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

public import dsubs_client.core.window;
public import dsubs_client.input.router: InputRouter;


/// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Window wnd);
}

/// Rendering thread wrapper, renders one window and dictates general form
/// of the rendering pipeline.
final class Render
{
	__gshared sfColor g_clearColor = sfColor(30, 30, 30, 255);

	private Window m_window;
	private InputRouter m_router;
	IWindowDrawer guiRender;
	IWindowDrawer worldRender;

	@property Window window() { return m_window; }
	@property InputRouter router() { return m_router; }

	private Thread m_worker;	/// rendering thread
	private bool m_stopFlag;	/// true when stop was requested

	this(Window wnd, InputRouter router)
	{
		assert(wnd);
		m_window = wnd;
		m_router = router;
		wnd.registerHandler(sfEvtClosed, (w, e) { this.stop(); });
	}

	/// start rendering thread
	void start(Mutex mutex)
	{
		if (m_worker && m_worker.isRunning)
			throw new Exception("Render already started");
		m_stopFlag = false;
		trace("Deactivating window GL context in parent thread...");
		sfRenderWindow_setActive(m_window.wnd, false);
		trace("OK");
		info("Starting render thread...");
		m_worker = new Thread((){ render(mutex); }).start();
		info("OK");
	}

	/// non-blocking stop
	void stopAsync() { m_stopFlag = true; }

	/// blocking stop
	void stop()
	{
		m_stopFlag = true;
		if (m_worker && m_worker.isRunning)
			m_worker.join(false);
	}

	/// Thread function
	private void render(scope Mutex mutex)
	{
		try
		{
			while (!m_stopFlag)
			{
				m_window.resetView();
				sfRenderWindow_clear(m_window.wnd, g_clearColor);
				{
					mutex.lock();
					scope(exit) mutex.unlock();
					if (m_router)
						m_router.simulateMouseMove();
					if (worldRender)
						worldRender.draw(m_window);
					if (guiRender)
						guiRender.draw(m_window);
				}
				// present backbuffer, blocks until vsync
				sfRenderWindow_display(m_window.wnd);
			}
		}
		catch (Throwable err)
		{
			error("Render loop crashed: ", err.toString);
		}
		trace("Exiting render loop, stop_flag is ", m_stopFlag);
	}
}
