module dsubs_client.gui.manager;

import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_client.core.component;
import dsubs_client.render.render;


// Thing that draws gui components on the window
class GuiManager: ComponentManager!"Gui", IWindowDrawer
{
	void draw(Render ctx, Window wnd) {}
}
