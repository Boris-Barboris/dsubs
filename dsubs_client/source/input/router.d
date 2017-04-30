module dsubs_client.input.inputhandler;

import std.experimental.logger;

import derelict.sfml2.window;

public import dsubs_client.core.component;
public import dsubs_client.core.window;


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

	void route_event(const sfEvent* evt)
	{
		HandleResult res = gui_router.handleEvent(this, evt);
		if (!res.passThrough)
			return;
		res = overlay_router.handleEvent(this, evt);
		if (!res.passThrough)
			return;
		res = world_router.handleEvent(this, evt);
	}
}
