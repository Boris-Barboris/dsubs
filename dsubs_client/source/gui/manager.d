module dsubs_client.gui.manager;

import std.container: DList;
import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.core.sfml;
import dsubs_client.input.router;
import dsubs_client.render.render;


struct GuiHandleResult
{
	// result to return to router
	HandleResult res;
	// component that captured the event, null if was not captured
	GuiElement interceptor;
}

// Root of gui element tree, that is stored in the manager
class Panel
{
	GuiElement root;

	// last mouse event reciever, that will be tried first
	private GuiElement mouse_event_cache;

	this(GuiElement root)
	{
		this.root = root;
	}

	void draw(Window wnd) { root.draw(wnd); }

	void GuiHandleResult handleEvent(const sfEvent* evt)
	{
		int x, y, delta;
		sfMouseButton btn;
		if (isMousePosEvent(evt, x, y, btn, delta))
		{
			// it's mouse-related positioned event
			GuiHandleResult res;
			if (mouse_event_cache)
				res = mouse_event_cache.handleEvent(evt, x, y, btn, delta);
			if (res.interceptor)
			{
				// cache hit
				mouse_event_cache = res.interceptor;	// do we need this?
				return res;
			}
			// cache miss
			res = root.handleEvent(evt, x, y, btn, delta);
			if (res.interceptor)
				mouse_event_cache = res.interceptor;
			else
				mouse_event_cache = null;	// we're outside of a panel probably
			return res;
		}
		// we don't handle any other events in trees. Keyboard input is done via
		// focus mechanics
		return GuiHandleResult(HandleResult(), null);
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
		}
		// Handle events from top to bottom
		foreach (panel; retro(active_panels))
		{
			res = panel.handleEvent(evt);
			if (res.interceptor)
			{
				// there was actual entity, that captured the event. Stop here.
				return res.res;
			}
			if (!res.passThrough)
				return res.res;
		}
		return HandleResult();
	}

	// element that has keyboard focus, and will recieve Text events
	GuiElement kb_focus;
}
