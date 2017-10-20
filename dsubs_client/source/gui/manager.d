module dsubs_client.gui.manager;

import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.containers.dlist;

public import dsubs_client.core.component;
import dsubs_client.lib.sfml;
import dsubs_client.core.utils;
public import dsubs_client.gui.element;
import dsubs_client.input.router;
import dsubs_client.render.render;


// Gui explicitly handles only mouse events.
// This structure is returned by GuiElements when trying to
// route the mouse event. Interceptor is a tree leaf, that was placed under
// the cursor. It may choose to let the event go through however, by setting
// mouse_transparent to true.
struct GuiRouteResult
{
	GuiElement interceptor;
	bool mouse_transparent = true;
}

// One element tree instance, structural unit of the Gui manager.
class Panel
{
	protected GuiElement _root;
	@property GuiElement root() const { return _root; }
	// if true, mouse click will push this panel on top of the stack.
	// useful for windows.
	bool mouse_zboost = false;

	// active flag to quickly switch panels on and off.
	bool active = true;
	// last mouse event reciever, that will be tried first
	protected GuiElement mouse_event_cache;

	protected GuiManager _manager;
	@property GuiManager manager() const { return _manager; }

	this(GuiManager mgr, GuiElement root)
	{
		_manager = mgr;
		_root = root;
	}

	void draw(Window wnd) { _root.draw(wnd); }

	GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		if (mouse_event_cache)
		{
			res = mouse_event_cache.routeMousePos(evt, x, y);
			if (res.interceptor)
			{
				// cache hit, update it
				mouse_event_cache = res.interceptor;
				return res;
			}
			else
			{
				// cache miss
				log("Panel mouse cache miss");
				mouse_event_cache = null;
			}
		}
		// no cached handler
		res = _root.routeMousePos(evt, x, y);
		mouse_event_cache = res.interceptor;
		return res;
	}

	void handleWindowResize(const sfSizeEvent* evt)
	{
		if (_root.sizeType == SizeType.GREEDY)	// greedy roots are fullscreen
			_root.size(vec2i(evt.width, evt.height));
	}
}

// Thing that draws gui components on the window and routes window events
final class GuiManager: IWindowDrawer, IWindowEventSubrouter
{
	private Window _window;
	@property Window window() const { return _window; }

	this(Window wnd)
	{
		_window = wnd;
	}

	void draw(Render ctx, Window wnd)
	{
		// reset window view to default one
		// sfRenderWindow_setView(wnd.ptr, wnd.view);
		// deepest panels first
		foreach (panel; active_panels)
			panel.draw(wnd);
	}

	auto active_panels()
	{
		return filter!(a => a.active)(panels[]);
	}

	auto retro_active_panels()
	{
		return filter!(a => a.active)(retro(panels[]));
	}

	// Z-ordered list of GuiElement trees. First (front) element is the deepest one.
	DList!Panel panels;

	// In GUI we register only tree roots, and we do it manually,
	// not in the component's constructor.
	void addAsPanel(GuiElement root)
	{
		panels.insertBack(new Panel(this, root));
	}

	RouteResult routeMousePos(Router ctx, const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		// look for reciever from top to bottom of z-ordered panel stack
		for (auto i = panels.end(); !i.end; i.prev)
		{
			if (!i.val.active)
				continue;
			auto panel = i.val;
			res = panel.routeMousePos(evt, x, y);
			if (res.interceptor)
			{
				// event-transparent elements only update panel's lookup cache
				if (res.mouse_transparent)
					continue;
				if (evt.type == sfEvtMouseButtonPressed && panel.mouse_zboost)
				{
					// default behaviour of moving clicked panel to
					// the top of z-stack
					panels.remove(i);
					panels.insertBack(panel);
				}
				return RouteResult(res.interceptor);
			}
		}
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Router ctx, const sfEvent* evt)
	{
		// GUI captures keyboard only through focus mechanics
		return RouteResult(null);
	}

	void handleWindowResize(Router ctx, Window wnd, const sfSizeEvent* evt)
	{
		// TODO: resize handling for greedy and fraction-sized panels, out-of
		// window border check etc.
		foreach (panel; panels[])
			panel.handleWindowResize(evt);
	}
}
