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


struct GuiHandleResult
{
	// result to return to main router
	HandleResult res;
	// Component, that captured the event. For mouse events. this is the
	// deepest element right under the cursor. Null for mouse events means, that
	// cursor is out of bounds. Always null for keyboard-related events.
	GuiElement interceptor;
}

// One flat element tree instance, structural unit of the Gui manager.
class Panel
{
	GuiElement root;

	// last mouse event reciever, that will be tried first
	package GuiElement mouse_event_cache;

	this(GuiElement root)
	{
		this.root = root;
	}

	void draw(Window wnd) { root.draw(wnd); }

	GuiHandleResult handleMousePosEvent(const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
	{
		GuiHandleResult res;
		if (mouse_event_cache)
		{
			res = mouse_event_cache.handleMousePosEvent(evt, x, y, btn, delta);
			if (res.interceptor)
			{
				// cache hit
				if (mouse_event_cache != res.interceptor)
				{
					// mouse switched from one element to another
					mouse_event_cache = res.interceptor;
				}
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
		res = root.handleMousePosEvent(evt, x, y, btn, delta);
		if (res.interceptor)
			mouse_event_cache = res.interceptor;
		return res;
	}
}

// Thing that draws gui components on the window and routes window events
class GuiManager: ComponentManager!"Gui", IWindowDrawer, IWindowEventHandler
{
	package Window wnd;
	package Router rt;

	this(Window wnd, Router rt)
	{
		this.wnd = wnd;
		this.rt = rt;
		if (rt)
			rt.gui_router = this;
	}

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
			panels.removePred(a => a.root.deleted);
		}
	}

	// Event handling
	HandleResult handleEvent(Router ctx, const sfEvent* evt)
	{
		GuiHandleResult res;
		int x, y, delta;
		sfMouseButton btn;
		if (isMousePosEvent(evt, x, y, btn, delta))
		{
			// Handle events from top to bottom
			foreach (panel; retro_active_panels)
			{
				res = panel.handleMousePosEvent(evt, x, y, btn, delta);
				if (res.interceptor)
				{
					// someone is actually under the mouse, we should
					// set the underCursor focus of the router
					ctx.cursorPointed(res.interceptor);
					if (evt.type == sfEvtMouseButtonPressed)
					{
						// default behaviour of moving clicked panel to
						// the top of z-stack
						panels.removePredFirst(a => a is panel);
						panels.insertBack(panel);
					}
					return res.res;
				}
			}
		}
		return HandleResult(true, true);
	}
}
