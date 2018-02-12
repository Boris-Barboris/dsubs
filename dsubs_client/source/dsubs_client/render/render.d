module dsubs_client.render.render;

import core.time;
import core.thread;
import core.sync.mutex;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.event;

import dsubs_client.core.window;
import dsubs_client.input.router: InputRouter;


/// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Window wnd, long usecsDelta);
}

/// Rendering thread wrapper, renders one window and dictates general form
/// of the rendering pipeline.
final class Render
{
	/// render clears window with this color at the beginning of each frame
	sfColor clearColor = sfColor(30, 30, 30, 255);

	private Window m_window;
	private InputRouter m_router;

	IWindowDrawer guiRender;
	IWindowDrawer worldRender;

	@property Window window() { return m_window; }
	@property InputRouter router() { return m_router; }

	private Thread m_worker;	/// rendering thread
	private bool m_stopFlag;	/// true when rendering thread stop was requested

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

	// these events are fired while holding render lock
	Event!(void delegate(long usecsDelta)) onPreRender;
	Event!(void delegate(long usecsDelta)) onPreGuiRender;
	Event!(void delegate(long usecsDelta)) onPostRender;

	/// clear handlers from on..Render events
	void clearHandlers()
	{
		onPreRender.clear();
		onPreGuiRender.clear();
		onPostRender.clear();
	}

	private float m_avgFps = 0.0f;
	@property float avgFps() const { return m_avgFps; }
	enum int FPS_UPDATE_FREQ = 60;

	/// Thread function
	private void render(scope Mutex mutex)
	{
		try
		{
			MonoTime lastFpsMark = MonoTime.currTime;
			MonoTime curTime = lastFpsMark;
			MonoTime prevTime = curTime;
			long usecsDelta = 0;
			int frameCounter = 0;
			while (!m_stopFlag)
			{
				m_window.resetView();
				sfRenderWindow_clear(m_window.wnd, clearColor);
				synchronized(mutex)
				{
					onPreRender(usecsDelta);
					if (m_router)
						m_router.simulateMouseMove();
					if (worldRender)
					{
						worldRender.draw(m_window, usecsDelta);
						m_window.resetView();
					}
					onPreGuiRender(usecsDelta);
					if (guiRender)
						guiRender.draw(m_window, usecsDelta);
					onPostRender(usecsDelta);
				}
				// present backbuffer, blocks until vsync
				sfRenderWindow_display(m_window.wnd);
				// update timings
				prevTime = curTime;
				curTime = MonoTime.currTime;
				usecsDelta = (curTime - prevTime).total!"usecs";
				// update fps
				if (++frameCounter > FPS_UPDATE_FREQ - 1)
				{
					// 60 frames were rendered
					long totalMsecs = (curTime - lastFpsMark).total!"msecs";
					m_avgFps = FPS_UPDATE_FREQ * 1000.0f / totalMsecs;
					frameCounter = 0;
					lastFpsMark = curTime;
				}
			}
		}
		catch (Throwable err)
		{
			error("Render loop crashed: ", err.toString);
		}
		trace("Exiting render loop, stop_flag is ", m_stopFlag);
	}
}
