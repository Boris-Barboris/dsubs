module dsubs_client.gui.manager;

import std.container: DList;
import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
public import dsubs_client.gui.element;
import dsubs_client.input.router;
import dsubs_client.render.render;


struct GuiHandleResult
{
	// result to return to router
	HandleResult res;
	// component that captured the event, null otherwise
	GuiElement interceptor;

	this(bool pass, GuiElement intec)
	{
		res = HandleResult(pass);
		interceptor = intec;
	}
}

// Root of gui element tree, that is stored in the manager
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

	GuiHandleResult handleEvent(const sfEvent* evt)
	{
		int x, y, delta;
		sfMouseButton btn;
		if (isMousePosEvent(evt, x, y, btn, delta))
		{
			// it's mouse-related positioned event
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
						mouse_event_cache.handleMouseLeave();
						res.interceptor.handleMouseEnter();
						mouse_event_cache = res.interceptor;
					}
					return res;
				}
				else
				{
					// cache miss
					log("Panel mouse cache miss");
					mouse_event_cache.handleMouseLeave();
					mouse_event_cache = null;
				}
			}
			// no cached handler
			res = root.handleMousePosEvent(evt, x, y, btn, delta);
			if (res.interceptor)
			{
				mouse_event_cache = res.interceptor;
				mouse_event_cache.handleMouseEnter();
			}
			return res;
		}
		if (evt.type == sfEvtMouseLeft)
		{
			if (mouse_event_cache)
			{
				mouse_event_cache.handleMouseLeave();
				mouse_event_cache = null;
			}
		}
		// we don't handle any other events in trees. Keyboard input is done via
		// focus mechanics
		return GuiHandleResult(true, null);
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
			panels = DList!Panel(remove!(a => a.root.deleted)(panels[]));
		}
	}

	// Event handling
	HandleResult handleEvent(Router ctx, const sfEvent* evt)
	{
		GuiHandleResult res;
		if (isKeyboardEvent(evt))
		{
			// keyboard event, pass it to focused element if possible
			if (kb_focus)
				return kb_focus.handleKeyboard(evt).res;
			return HandleResult();
		}
		// Handle events from top to bottom
		foreach (panel; retro_active_panels)
		{
			res = panel.handleEvent(evt);
			if (res.interceptor)
			{
				// there was an actual entity, that captured the event.
				return res.res;
			}
			if (!res.res.passThrough)
				return res.res;
		}
		return HandleResult();
	}

	// element that has keyboard focus, and will recieve Text events.
	GuiElement kb_focus;
}
