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


// Gui explicitly handles only mouse events, keyboard is done via
// focus mechanics.
struct GuiHandleResult
{
	// result to return to main router
	HandleResult res;
	// GuiElement, that captured the event. For mouse events. this is the
	// deepest element right under the cursor. Null for mouse events means, that
	// cursor is out of bounds.
	GuiElement interceptor;
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

	GuiHandleResult handleMousePosEvent(const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
	{
		GuiHandleResult res;
		if (mouse_event_cache)
		{
			res = mouse_event_cache.handleMousePosEvent(evt, x, y, btn, delta);
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
		res = root.handleMousePosEvent(evt, x, y, btn, delta);
		if (res.interceptor)
			mouse_event_cache = res.interceptor;
		return res;
	}
}

// Thing that draws gui components on the window and routes window events
class GuiManager: ComponentManager!"Gui", IWindowDrawer, IWindowEventHandler
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
			// Handle events from top to bottom of z-ordered panel stack
			foreach (panel; retro_active_panels)
			{
				res = panel.handleMousePosEvent(evt, x, y, btn, delta);
				if (res.interceptor)
				{
					// event-transparent elements update panel cache,
					// but are not focus-interactive
					if (res.res.passThrough)
						continue;
					// we should set the underCursor focus of the router
					Router.cursorPointed(res.interceptor);
					if (evt.type == sfEvtMouseButtonPressed &&
						res.interceptor !is Router.kbFocus)
					{
						// mouse click on something that is not event-transparent
						// and is not keyboard-focused element, wich means
						// we should unset keyboard focus
						Router.kbFocus(null);
					}
					if (evt.type == sfEvtMouseButtonPressed && panel.mouse_zboost)
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
