module dsubs_client.input.router;

import std.experimental.logger;

import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
public import dsubs_client.core.window;


// Generic input reciever
interface IInputReciever
{
	void handleMouseEnter();
	void handleMouseLeave();
	// by focus we mean keyboard input priority. Keyboard events first are
	// routed in this element, and then to other ones.
	void handleKbFocusGain();
	void handleKbFocusLoss();
	// Objects can also request exclusive mouse event focus. Example: dragging
	void handleMouseFocusGain();
	void handleMouseFocusLoss();
	// exclusive keyboard handling method. Returns true when the objects wants to loose
	// focus.
	bool handleKeyboard(const sfEvent* evt);
	// exclusive mouse handling method. Returns true when the objects wants to loose
	// focus.
	bool handleMouse(const sfEvent* evt);
}

/// Result of event handling
struct HandleResult
{
	// Should the event be passed further down to lower levels?
	bool passThrough = true;	// pass by default
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
	protected IInputReciever _cursorFocus, _kbFocus, _mouseFocus;

	mixin template FocusAccessor(string field_name, string loose_name,
		string gain_name)
	{
		mixin("IInputReciever " ~ field_name ~ "() { return _" ~ field_name ~ ";};");
		mixin("void " ~ field_name ~ "(IInputReciever val) " ~
			"{ if (_" ~ field_name ~ " && _" ~ field_name ~ " !is val) _" ~
			field_name ~ "." ~ loose_name ~ "(); if (val) val." ~ gain_name ~
			"(); _" ~ field_name ~ " = val;");
	}

	mixin FocusAccessor!("cursorFocus", "handleMouseLeave", "handleMouseEnter");
	mixin FocusAccessor!("kbFocus", "handleKbFocusLoss", "handleKbFocusGain");
	mixin FocusAccessor!("mouseFocus", "handleMouseFocusLoss", "handleMouseFocusGain");

	Window window() { return _window; }

	this(Window wnd)
	{
		_window = wnd;
		// subscribe to events we may be interested in
		wnd.register_handler(sfEvtResized, &route_event);
		wnd.register_handler(sfEvtLostFocus, &route_event);
		wnd.register_handler(sfEvtTextEntered, &route_event);
		wnd.register_handler(sfEvtKeyPressed, &route_event);
		wnd.register_handler(sfEvtKeyReleased, &route_event);
		wnd.register_handler(sfEvtMouseWheelMoved, &route_event);
		wnd.register_handler(sfEvtMouseButtonPressed, &route_event);
		wnd.register_handler(sfEvtMouseButtonReleased, &route_event);
		wnd.register_handler(sfEvtMouseMoved, &route_event);
		wnd.register_handler(sfEvtMouseEntered, &route_event);
		wnd.register_handler(sfEvtMouseLeft, &route_event);
	}

	/// In dynamic, moving environment it's simpler to just generate
	/// mouseMove event every time screen is redrawn in order to get new
	/// object under the cursor. GUI router will have a good cache anyways.
	void simulate_mouse_move()
	{
		if (_window.hasFocus)
		{
			sfVector2i mp = sfMouse_getPositionRenderWindow(wnd);
			sfEvent move_event;
			move_event.type = sfEvtMouseMoved;
			move_event.x = mp.x;
			move_event.y = mp.y;
			route_event(&move_event);
		}
	}

	void clear_focus()
	{
		cursorFocus(null);
		kbFocus(null);
		mouseFocus(null);
	}

	void route_event(const sfEvent* evt)
	{
		HandleResult res;
		if (_kbFocus && isKeyboardEvent(evt))
		{
			bool give_focus = _kbFocus.handleKeyboard(evt);
			if (give_focus)
				kbFocus(null);
			else
				return;
		}
		if (_mouseFocus && isMousePosEvent(evt))
		{
			bool give_focus = _mouseFocus.handleMouse(evt);
			if (give_focus)
				mouseFocus(null);
			else
				return;
		}
		if (evt.type == sfEvtLostFocus)
		{
			clear_focus();
			return;
		}
		if (evt.type == sfEvtMouseLeft)
			cursorFocus(null);

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
