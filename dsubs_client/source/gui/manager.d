module dsubs_client.gui.manager;

import std.experimental.logger;
import std.algorithm;
import std.range;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.containers.dlist;

import dsubs_client.core.utils;
import dsubs_client.lib.sfml;
import dsubs_client.input.router;
import dsubs_client.render.render: IWindowDrawer;
import dsubs_client.gui.element;


/** Gui router explicitly handles only mouse events.
This structure is returned by GuiElements when trying to
route the mouse event. Interceptor is a tree leaf, that was placed under
the cursor. The leaf may choose to let the event go through, by setting
mouse_transparent to true. */
package struct GuiRouteResult
{
	GuiElement mouseReciever;
	bool mouseTransparent = true;
}

/// Primitive panel, wich consists of one GuiElement tree.
class Panel
{
	protected GuiElement m_root;
	@property GuiElement root() { return m_root; }
	
	/// If true, mouse click will push this panel on top of the stack.
	bool zboost = false;

	/// previous mouse event reciever, for quick lookup
	protected GuiElement m_mouseCache;

	this(GuiElement root)
	{
		assert(root);
		m_root = root;
	}

	protected void draw(Window wnd) { m_root.draw(wnd); }

	protected GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		if (m_mouseCache)
		{
			res = m_mouseCache.routeMousePos(evt, x, y);
			if (res.mouseReciever)
			{
				// cache hit, update it
				m_mouseCache = res.mouseReciever;
				return res;
			}
			else
			{
				// cache miss
				//trace("Panel mouse cache miss");
				m_mouseCache = null;
			}
		}
		// no cached handler
		res = m_root.routeMousePos(evt, x, y);
		m_mouseCache = res.mouseReciever;
		return res;
	}

	protected void handleWindowResize(const sfSizeEvent* evt)
	{
		// greedy roots are fullscreen by convention
		if (m_root.layoutType == LayoutType.GREEDY)
		{
			m_root.position = vec2i(0, 0);
			m_root.size = vec2i(evt.width, evt.height);
		}
	}
}

/// Container for all gui elements on one window. Draws them
/// and dispatches input. Implements z-ordering.
final class GuiManager: IWindowDrawer, IWindowEventSubrouter
{
	private Window m_wnd;
	@property Window window() { return m_wnd; }

	this(Window wnd)
	{
		m_wnd = wnd;
	}

	void draw(Window wnd)
	{
		// deepest panels first
		foreach (panel; panels[])
			panel.draw(wnd);
	}

	// Z-ordered list of GuiElement trees. 
	// First (front) element is the deepest one.
	private DList!Panel panels;

	/// register a panel in a manager and place it on top of all existing panels
	void addPanel(Panel p)
	{
		panels.insertBack(p);
		// initial shakedown in order to befriend new panel 
		// with current window size
		sfSizeEvent fake = sfSizeEvent(sfEvtResized, m_wnd.width, m_wnd.height);
		p.handleWindowResize(&fake);
	}

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		GuiRouteResult res;
		// look for reciever from top to bottom of z-ordered panel stack
		for (auto i = panels.end(); !i.end; i.prev)
		{
			Panel panel = i.val;
			res = panel.routeMousePos(evt, x, y);
			if (res.mouseReciever)
			{
				// event-transparent elements only update panel's lookup cache
				if (res.mouseTransparent)
					continue;
				if (evt.type == sfEvtMouseButtonPressed && panel.zboost)
				{
					// default behaviour of moving clicked panel to
					// the top of z-stack
					panels.remove(i);
					panels.insertBack(panel);
				}
				return RouteResult(res.mouseReciever);
			}
		}
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		// GUI captures keyboard only through focus mechanics
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt)
	{
		// TODO: resize handling for greedy and fraction-sized panels, out-of
		// window border check etc.
		foreach (panel; panels[])
			panel.handleWindowResize(evt);
	}
}
