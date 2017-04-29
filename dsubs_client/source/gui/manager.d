module dsubs_client.gui.manager;

import std.container: DList;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_client.core.component;
import dsubs_client.render.render;


// Something that is drawn on gui layer
class GuiComponent: Component!"Gui"
{
	this(ManagerType manager)
	{
		super(manager);
	}

	abstract void draw(Window wnd);
}

// Thing that draws gui components on the window
class GuiManager: ComponentManager!"Gui", IWindowDrawer
{
	void draw(Render ctx, Window wnd)
	{
		// we render from deepest elements
		foreach (panel; panels)
		{
			if (!panel.active)
				continue;
			panel.draw(wnd);
		}
	}

	void addAsPanel(GuiComponent panel)
	{
		panels.insertBack(panel);
	}

	// Z-ordered list of GuiElement tree roots. They may be windows, may be
	// full-screen pages. First element is the deepest one.
	DList!GuiComponent panels;

	// TODO: add panel list cleaning and reordering
}
