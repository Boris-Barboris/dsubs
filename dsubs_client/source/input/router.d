module dsubs_client.input.router;

import std.experimental.logger;

import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
public import dsubs_client.core.window;


// Generic input event reciever
interface IInputReciever
{
	// When player moves his mouse, MouseMove event is generated and passed to
	// input routers. Additionaly, every frame artificial event is generated
	// in order to react to scene itself changing under the cursor. When mouse
	// first enters reciever, he gets MouseEnter call from the router.
	// When mouse leaves window, reciever, or reciever itself moves out
	// of the cursor, it gets MouseLeave.
	void handleMouseEnter();
	void handleMouseLeave();
	// By focus we mean keyboard input priority. Keyboard events first are
	// routed in this element, and only then to other ones, if the element
	// desires. These two functions are called on keyboard focus gain\loss.
	void handleKbFocusGain();
	void handleKbFocusLoss();
	// Objects can also request exclusive mouse event focus. Example: dragging
	void handleMouseFocusGain();
	void handleMouseFocusLoss();
	// keyboard handling method.
	HandleResult handleKeyboard(const sfEvent* evt);
	// mouse handling method.
	HandleResult handleMouse(const sfEvent* evt);
}

/// Result of event handling
struct HandleResult
{
	// Should the event be passed further down to lower levels?
	bool passThrough = true;	// pass by default
	// don't want to loose focus by default. Relevant only for focused
	// recievers.
	bool give_focus = false;
}

/// Anything that can handle a WindowEvent
interface IWindowEventHandler
{
	HandleResult handleEvent(Router ctx, const sfEvent* evt);
}

/// Event router, that orderes window event handling by subsystems
class Router
{
	protected Window _window;
	IWindowEventHandler gui_router;
	IWindowEventHandler overlay_router;
	IWindowEventHandler world_router;
	IWindowEventHandler hotkey_router;

	// Focused components. Just assign them to what you need.
	static __gshared IInputReciever _cursorPointed, _kbFocus, _mouseFocus;

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
		wnd.register_handler(sfEvtResized, &route_event);
		wnd.register_handler(sfEvtTextEntered, &route_event);
		wnd.register_handler(sfEvtKeyPressed, &route_event);
		wnd.register_handler(sfEvtKeyReleased, &route_event);
		wnd.register_handler(sfEvtMouseWheelMoved, &route_event);
		wnd.register_handler(sfEvtMouseButtonPressed, &route_event);
		wnd.register_handler(sfEvtMouseButtonReleased, &route_event);
		//wnd.register_handler(sfEvtMouseMoved, &route_event);
		//wnd.register_handler(sfEvtMouseEntered, &route_event);
		// another special case:
		wnd.register_handler(sfEvtMouseLeft, (a) { cursorPointed(null); });
	}

	/// In dynamic, moving environment it's simpler to just generate
	/// mouseMove event every time screen is redrawn in order to get new
	/// object under the cursor. GUI router should have a good cache anyways.
	void simulate_mouse_move()
	{
		if (_window.hasFocus)
		{
			sfVector2i mp = sfMouse_getPositionRenderWindow(_window.ptr);
			sfEvent move_event;
			move_event.type = sfEvtMouseMoved;
			move_event.mouseMove.x = mp.x;
			move_event.mouseMove.y = mp.y;
			route_event(&move_event);
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

	void route_event(const sfEvent* evt)
	{
		HandleResult res;
		if (_kbFocus && isKeyboardEvent(evt))
		{
			res = _kbFocus.handleKeyboard(evt);
			if (res.give_focus)
				kbFocus(null);
			if (!res.passThrough)
				return;
		}
		if (_mouseFocus && isMousePosEvent(evt))
		{
			res = _mouseFocus.handleMouse(evt);
			if (res.give_focus)
				mouseFocus(null);
			if (!res.passThrough)
				return;
		}

		// main cascade of child routers
		if (gui_router)
		{
			res = gui_router.handleEvent(this, evt);
			if (!res.passThrough)
				return;
		}
		if (overlay_router)
		{
			res = overlay_router.handleEvent(this, evt);
			if (!res.passThrough)
				return;
		}
		if (world_router)
		{
			res = world_router.handleEvent(this, evt);
			if (!res.passThrough)
				return;
		}
		if (hotkey_router)
			res = hotkey_router.handleEvent(this, evt);
	}
}
