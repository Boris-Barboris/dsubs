module dsubs_client.input.router;

import std.experimental.logger;

import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
public import dsubs_client.core.window;


// Generic input event reciever
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
	// routed in this element.
	// These two functions are called on keyboard focus gain\loss.
	void handleKbFocusGain();
	void handleKbFocusLoss();
	// Recievers can also request exclusive mouse event focus. Example: dragging
	void handleMouseFocusGain();
	void handleMouseFocusLoss();
	// keyboard handling method.
	HandleResult handleKeyboard(const sfEvent* evt);
	// mouse handling method. We forbid to pass mouse events through recievers.
	void handleMousePos(const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta);
}

/// Event handling result
struct HandleResult
{
	// reciever may decide to pass some events further down the chain of routers
	bool passThrough = true;
}

/// Result of event routing via subrouter.
struct RouteResult
{
	// Entity that should recieve the event. Null sends event further down
	// the chain.
	IInputReciever reciever;
}

/// Anything that can route WindowEvent
interface IWindowEventSubrouter
{
	RouteResult routeMousePos(Router ctx, const sfEvent* evt, int x, int y);
	RouteResult routeKeyboard(Router ctx, const sfEvent* evt);
	void handleWindowResize(Router ctx, Window wnd, const sfSizeEvent* evt);
}

/// Event router, that orderes window event handling by subsystems
class Router
{
	protected Window _window;
	IWindowEventSubrouter gui_router;
	IWindowEventSubrouter overlay_router;
	IWindowEventSubrouter world_router;
	IWindowEventSubrouter hotkey_router;

	// Focused components. Just assign them to what you need.
	private static __gshared IInputReciever _cursorPointed, _kbFocus, _mouseFocus;

	mixin template FocusAccessor(string field_name, string loose_name,
		string gain_name)
	{
		mixin("static IInputReciever " ~ field_name ~ "() { return _" ~ field_name ~ ";}");
		mixin("static void " ~ field_name ~ "(IInputReciever val) " ~
			"{ if (_" ~ field_name ~ " !is val) { if (_" ~ field_name ~ ") _" ~
			field_name ~ "." ~	loose_name ~ "(); if (val) val." ~ gain_name ~
			"(); _" ~ field_name ~ " = val;}}");
	}

	mixin FocusAccessor!("cursorPointed", "handleMouseLeave", "handleMouseEnter");
	mixin FocusAccessor!("kbFocus", "handleKbFocusLoss", "handleKbFocusGain");
	mixin FocusAccessor!("mouseFocus", "handleMouseFocusLoss", "handleMouseFocusGain");

	Window window() { return _window; }

	this(Window wnd)
	{
		_window = wnd;
		// subscribe to events we may be interested in...
		// special case:
		wnd.register_handler(sfEvtLostFocus, &on_window_lost_focus);
		// one handler to rule them all:
		wnd.register_handler(sfEvtResized, &route_resize_event);
		wnd.register_handler(sfEvtTextEntered, &route_keyboard_event);
		wnd.register_handler(sfEvtKeyPressed, &route_keyboard_event);
		wnd.register_handler(sfEvtKeyReleased, &route_keyboard_event);
		wnd.register_handler(sfEvtMouseWheelMoved, &route_mouse_event);
		wnd.register_handler(sfEvtMouseButtonPressed, &route_mouse_event);
		wnd.register_handler(sfEvtMouseButtonReleased, &route_mouse_event);
		// we don't register MouseMoved handler, because we use artificial
		// event each frame.
		//wnd.register_handler(sfEvtMouseMoved, &route_event);
		// cursor-related special cases:
		wnd.register_handler(sfEvtMouseEntered, (a) { mouse_inside = true; });
		wnd.register_handler(sfEvtMouseLeft, (a)
			{ cursorPointed(null); mouse_inside = false; });
	}

	protected bool mouse_inside = true;

	/// In dynamic, moving environment it's simpler to just generate
	/// mouseMove event every time screen is redrawn in order to get new
	/// object under the cursor. GUI router should have a good cache anyways.
	void simulate_mouse_move()
	{
		if (_window.hasFocus && mouse_inside)
		{
			sfVector2i mp = sfMouse_getPositionRenderWindow(_window.ptr);
			sfEvent move_event;
			move_event.type = sfEvtMouseMoved;
			move_event.mouseMove.x = mp.x;
			move_event.mouseMove.y = mp.y;
			route_mouse_event(&move_event);
		}
	}

	void clear_focus()
	{
		cursorPointed(null);
		kbFocus(null);
		mouseFocus(null);
	}

	void on_window_lost_focus(const sfEvent* evt)
	{
		// When window loses focus, we simply clear all internal focuses.
		clear_focus();
	}

	void route_resize_event(const sfEvent* evt)
	{
		const sfSizeEvent* sevt = cast(const sfSizeEvent*) evt;
		if (gui_router)
			gui_router.handleWindowResize(this, _window, sevt);
		if (overlay_router)
			overlay_router.handleWindowResize(this, _window, sevt);
		if (world_router)
			world_router.handleWindowResize(this, _window, sevt);
	}

	void route_keyboard_event(const sfEvent* evt)
	{
		HandleResult res;
		if (_kbFocus)
		{
			res = _kbFocus.handleKeyboard(evt);
			if (!res.passThrough)
				return;
		}
		// routing cascade
		RouteResult rres;
		if (gui_router)
		{
			rres = gui_router.routeKeyboard(this, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(evt).passThrough)
					return;
		}
		if (overlay_router)
		{
			rres = overlay_router.routeKeyboard(this, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(evt).passThrough)
					return;
		}
		if (world_router)
		{
			rres = world_router.routeKeyboard(this, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(evt).passThrough)
					return;
		}
		if (hotkey_router)
		{
			rres = hotkey_router.routeKeyboard(this, evt);
			if (rres.reciever)
				if (!rres.reciever.handleKeyboard(evt).passThrough)
					return;
		}
	}

	private bool handle_mouse(RouteResult rres, const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
	{
		if (rres.reciever)
		{
			cursorPointed(rres.reciever);
			// mouse button events may also clear keyboard focus
			if (evt.type == sfEvtMouseButtonPressed && rres.reciever !is _kbFocus)
				kbFocus(null);
			rres.reciever.handleMousePos(evt, x, y, btn, delta);
			return true;
		}
		return false;
	}

	void route_mouse_event(const sfEvent* evt)
	{
		int x, y, delta;
		sfMouseButton btn;
		if (!isMousePosEvent(evt, x, y, btn, delta))
			throw new Exception("Mouse event is not actually a mouse event");
		HandleResult res;
		if (_mouseFocus)
		{
			_mouseFocus.handleMousePos(evt, x, y, btn, delta);
			return;
		}
		// routing cascade
		RouteResult rres;
		if (gui_router)
		{
			rres = gui_router.routeMousePos(this, evt, x, y);
			if (handle_mouse(rres, evt, x, y, btn, delta))
				return;
		}
		if (overlay_router)
		{
			rres = overlay_router.routeMousePos(this, evt, x, y);
			if (handle_mouse(rres, evt, x, y, btn, delta))
				return;
		}
		if (world_router)
		{
			rres = world_router.routeMousePos(this, evt, x, y);
			if (handle_mouse(rres, evt, x, y, btn, delta))
				return;
		}
		if (hotkey_router)
		{
			rres = hotkey_router.routeMousePos(this, evt, x, y);
			if (handle_mouse(rres, evt, x, y, btn, delta))
				return;
		}
		// mouse event was not captured by anything, nothing is under cursor
		cursorPointed(null);
		// click in emptyness clears keyboard focus
		if (evt.type == sfEvtMouseButtonPressed)
			kbFocus(null);
	}
}
