module dsubs_client.input.router;

import std.experimental.logger;

import derelict.sfml2.system;
import derelict.sfml2.window;
import derelict.sfml2.graphics;

import dsubs_client.lib.sfml;
public import dsubs_client.core.window;


/// Generic input event reciever
interface IInputReciever
{
	// Every frame artificial MouseMove event is generated
	// in order to react to scene itself changing under the cursor. When mouse
	// first enters reciever, he gets MouseEnter call from the router.
	// When mouse leaves window, reciever, or reciever itself moves out
	// of the cursor, it gets MouseLeave.
	void handleMouseEnter();
	void handleMouseLeave();
	// By focus we mean keyboard input priority. Keyboard events are
	// routed in this element first, then they go through the subrouter cascade.
	// These two functions are called on keyboard focus gain\loss.
	void handleKbFocusGain();
	void handleKbFocusLoss();
	// Recievers can also request exclusive mouse event focus. Example: dragging
	void handleMouseFocusGain();
	void handleMouseFocusLoss();
	// keyboard handling method. Reciever may state that he is uninterested in
	// this event.
	HandleResult handleKeyboard(Window wnd, const sfEvent* evt);
	// mouse handling method. We forbid to pass mouse events through recievers.
	void handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta);
}

/// Event handling result
struct HandleResult
{
	/// reciever may decide to pass some events further down the chain of routers
	bool passThrough = true;
}

/// Result of event routing via subrouter.
struct RouteResult
{
	/// Entity that should recieve the event. Null sends event further down
	/// the chain.
	IInputReciever reciever;
}

/// Particular subsystem should implement this interface, that allows to
/// select one particular component from many.
interface IWindowEventSubrouter
{
	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y);
	RouteResult routeKeyboard(Window wnd, const sfEvent* evt);
	void handleWindowResize(Window wnd, const sfSizeEvent* evt);
}

/// Window event router
final class InputRouter
{
	// subrouters in natural order:
	IWindowEventSubrouter guiRouter;
	IWindowEventSubrouter worldRouter;
	IWindowEventSubrouter hotkeyRouter;

	// Focused components. Just assign them to what you need. Focused
	// components are global and static. Only one reciever is under cursor.
	// Only one reciever is focused. Only one window is actively getting
	// events.
	private static __gshared IInputReciever
		g_underCursor, g_kbFocused, g_mouseFocused;

	static @property IInputReciever underCursor() { return g_underCursor; }
	static @property IInputReciever underCursor(IInputReciever rhs)
	{
		if (g_underCursor !is rhs)
		{
			if (g_underCursor !is null)
				g_underCursor.handleMouseLeave();
			if (rhs !is null)
				rhs.handleMouseEnter();
		}
		return g_underCursor = rhs;
	}

	static @property IInputReciever kbFocused() { return g_kbFocused; }
	static @property IInputReciever kbFocused(IInputReciever rhs)
	{
		if (g_kbFocused !is rhs)
		{
			if (g_kbFocused !is null)
				g_kbFocused.handleKbFocusLoss();
			if (rhs !is null)
				rhs.handleKbFocusGain();
		}
		return g_kbFocused = rhs;
	}

	static @property IInputReciever mouseFocused() { return g_mouseFocused; }
	static @property IInputReciever mouseFocused(IInputReciever rhs)
	{
		if (g_mouseFocused !is rhs)
		{
			if (g_mouseFocused !is null)
				g_mouseFocused.handleMouseFocusLoss();
			if (rhs !is null)
				rhs.handleMouseFocusGain();
		}
		return g_mouseFocused = rhs;
	}

	private Window m_window;
	@property Window window() { return m_window; }

	this(Window wnd)
	{
		assert(wnd);
		m_window = wnd;
		m_wndHasFocus = wnd.hasFocus;

		// subscribe to events we may be interested in
		wnd.registerHandler(sfEvtLostFocus, &onWindowLostFocus);
		wnd.registerHandler(sfEvtGainedFocus, &onWindowGainFocus);
		wnd.registerHandler(sfEvtMouseEntered, &onMouseEnter);
		wnd.registerHandler(sfEvtMouseLeft, &onMouseLeave);
		wnd.registerHandler(sfEvtResized, &routeResizeEvent);
		wnd.registerHandler(sfEvtTextEntered, &routeKeyboardEvent);
		wnd.registerHandler(sfEvtKeyPressed, &routeKeyboardEvent);
		wnd.registerHandler(sfEvtKeyReleased, &routeKeyboardEvent);
		wnd.registerHandler(sfEvtMouseWheelMoved, &routeMouseEvent);
		wnd.registerHandler(sfEvtMouseButtonPressed, &routeMouseEvent);
		wnd.registerHandler(sfEvtMouseButtonReleased, &routeMouseEvent);
		// we don't register MouseMoved handler, because we create artificial
		// event each frame.
	}

	private bool m_mouseInside = true;
	private bool m_wndHasFocus;

	/// In dynamic, moving environment it's simpler to just generate
	/// mouseMove event every time screen is redrawn in order to get new
	/// object under the cursor. Rrouters should have a good caching mechanism.
	void simulateMouseMove()
	{
		if (m_wndHasFocus && (m_mouseInside || g_mouseFocused))
		{
			sfVector2i mp = sfMouse_getPositionRenderWindow(m_window.wnd);
			sfEvent moveEvent;
			moveEvent.type = sfEvtMouseMoved;
			moveEvent.mouseMove.x = mp.x;
			moveEvent.mouseMove.y = mp.y;
			routeMouseEvent(m_window, &moveEvent);
		}
	}

	void clearFocused()
	{
		underCursor = null;
		kbFocused = null;
		mouseFocused = null;
	}

private:

	void onWindowLostFocus(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		// When window loses focus, we simply clear all internal focuses.
		clearFocused();
		m_wndHasFocus = false;
	}

	void onWindowGainFocus(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		m_wndHasFocus = true;
	}

	void onMouseEnter(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		m_mouseInside = true;
	}

	void onMouseLeave(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		underCursor = null;
		m_mouseInside = false;
	}

	void routeResizeEvent(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		const sfSizeEvent* sevt = cast(const sfSizeEvent*) evt;
		if (guiRouter)
			guiRouter.handleWindowResize(wnd, sevt);
		if (worldRouter)
			worldRouter.handleWindowResize(wnd, sevt);
	}

	void routeKeyboardEvent(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		HandleResult res;
		if (g_kbFocused)
		{
			res = g_kbFocused.handleKeyboard(wnd, evt);
			if (!res.passThrough)
				return;
		}
		// routing cascade
		RouteResult rres;
		if (guiRouter)
		{
			rres = guiRouter.routeKeyboard(wnd, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(wnd, evt).passThrough)
					return;
		}
		if (worldRouter)
		{
			rres = worldRouter.routeKeyboard(wnd, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(wnd, evt).passThrough)
					return;
		}
		if (hotkeyRouter)
		{
			rres = hotkeyRouter.routeKeyboard(wnd, evt);
			if (rres.reciever)
				rres.reciever.handleKeyboard(wnd, evt);
		}
	}

	static bool handleMouse(Window wnd, RouteResult rres, const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
	{
		if (rres.reciever)
		{
			underCursor = rres.reciever;
			// mouse button events also clear keyboard focus
			if (evt.type == sfEvtMouseButtonPressed &&
				rres.reciever != kbFocused)
			{
				kbFocused = null;
			}
			rres.reciever.handleMousePos(wnd, evt, x, y, btn, delta);
			return true;
		}
		return false;
	}

	void routeMouseEvent(Window wnd, const sfEvent* evt)
	{
		assert(wnd == m_window);
		int x, y, delta;
		sfMouseButton btn;
		if (!isMousePosEvent(evt, x, y, btn, delta))
			assert(0, "Mouse event is not actually a mouse event");
		if (g_mouseFocused)
		{
			g_mouseFocused.handleMousePos(wnd, evt, x, y, btn, delta);
			return;	// no passthrough for mouse
		}
		// routing cascade
		if (guiRouter)
		{
			RouteResult rres = guiRouter.routeMousePos(wnd, evt, x, y);
			if (handleMouse(wnd, rres, evt, x, y, btn, delta))
				return;
		}
		if (worldRouter)
		{
			RouteResult rres = worldRouter.routeMousePos(wnd, evt, x, y);
			if (handleMouse(wnd, rres, evt, x, y, btn, delta))
				return;
		}
		// mouse event was not captured by anything, nothing is under cursor
		underCursor = null;
		// click in emptyness clears keyboard focus
		if (evt.type == sfEvtMouseButtonPressed)
			kbFocused = null;
	}
}
