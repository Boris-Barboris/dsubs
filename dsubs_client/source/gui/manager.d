module dsubs_client.gui.manager;

import std.container: DList;
import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

public import dsubs_client.core.component;
import dsubs_client.input.router;
import dsubs_client.render.render;


// Something that is drawn on gui layer
class GuiComponent: Component!"Gui"
{
	this(GuiManager manager)
	{
		super(manager);
	}

	abstract void draw(Window wnd);

	abstract HandleResult handleEvent(const sfEvent* evt);
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
		return filter!(a => a.active)(panels[]);
	}

	// Z-ordered list of GuiElement tree roots. They may be windows, may be
	// full-screen pages. First element is the deepest one.
	DList!GuiComponent panels;

	// In GUI we register only tree roots, and we do it manually,
	// not in the component's constructor.
	void addAsPanel(GuiComponent panel)
	{
		synchronized (this)
		{
			panels.insertBack(panel);
		}
	}

	override void clear_disposed()
	{
		synchronized (this)
		{
			panels = DList!GuiComponent(remove!(a => a.deleted)(panels[]));
		}
	}

	// Event handling
	HandleResult handleEvent(Router ctx, const sfEvent* evt)
	{
		HandleResult res;
		// Handle events from top to bottom
		foreach (panel; retro(active_panels))
		{
			res = panel.handleEvent(evt);
			if (!res.passThrough)
				return res;
		}
		return res;
	}
}
