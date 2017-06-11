module dsubs_client.gui.manager;

import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.containers.dlist;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
import dsubs_client.core.utils;
public import dsubs_client.gui.element;
import dsubs_client.input.router;
import dsubs_client.render.render;


// Gui explicitly handles only mouse events
struct GuiRouteResult
{
	GuiElement interceptor;
	bool mouse_transparent = true;
}

// One flat element tree instance, structural unit of the Gui manager.
class Panel
{
	GuiElement root;
	// if true, mouse click will push this panel on top of the stack.
	// usefull for windows.
	bool mouse_zboost = true;
	// last mouse event reciever, that will be tried first
	package GuiElement mouse_event_cache;

	this(GuiElement root)
	{
		this.root = root;
	}

	void draw(Window wnd) { root.draw(wnd); }

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
		res = root.routeMousePos(evt, x, y);
		mouse_event_cache = res.interceptor;
		return res;
	}
}

// Thing that draws gui components on the window and routes window events
class GuiManager: ComponentManager!"Gui", IWindowDrawer, IWindowEventSubrouter
{
	void draw(Render ctx, Window wnd)
	{
		// deepest panels first
		foreach (panel; active_panels)
			panel.draw(wnd);
	}

	auto active_panels()
	{
		return filter!(a => a.root.active)(panels[]);
	}

	auto retro_active_panels()
	{
		return filter!(a => a.root.active)(retro(panels[]));
	}

	// Z-ordered list of GuiElement tree roots. They may be windows, may be
	// full-screen pages. First element is the deepest one.
	DList!Panel panels;

	// In GUI we register only tree roots, and we do it manually,
	// not in the component's constructor.
	void addAsPanel(GuiElement root)
	{
		synchronized (this)
		{
			panels.insertBack(new Panel(root));
		}
	}

	override void clear_disposed()
	{
		synchronized (this)
		{
			panels.removeAll!(a => a.root.deleted);
		}
	}

	RouteResult routeMousePos(Router ctx, const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		// look for reciever from top to bottom of z-ordered panel stack
		foreach (panel; retro_active_panels)
		{
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
					panels.removeFirst!(a => a is panel);
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
		// window border check
	}
}
