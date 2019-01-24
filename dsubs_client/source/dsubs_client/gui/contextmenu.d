module dsubs_client.gui.contextmenu;

import std.algorithm;

import derelict.sfml2.window;
import derelict.sfml2.graphics;

import dsubs_client.common;
import dsubs_client.gui.element;
import dsubs_client.gui.div;
import dsubs_client.gui.button;
import dsubs_client.gui.label;
import dsubs_client.gui.manager;


/// Context menu, tipically invoked by right click. Can be nested.
/// Is responsible for it's own visibility on the window.
final class ContextMenu: Panel
{
	@property Div rootDiv() { return cast(Div) root; }

	this(Button[] elements, int rowHeight = 22)
	{
		Div div = vDiv(cast(GuiElement[]) elements);
		div.fixedSize = vec2i(100, (rowHeight * elements.length).to!int);
		// now adapt div width to max content size of buttons
		float maxContentWidth = elements.map!(
			e => (e.contentWidth + 2 * e.padding)).reduce!(max);
		div.fixedSize = vec2i(lrint(maxContentWidth).to!int, div.size.y);
		div.backgroundColor = sfColor(15, 15, 15, 255);
		// handle a click outside of the context menu
		div.onMouseDown += (int x, int y, sfMouseButton btn) {
			if (!div.rectContainsPoint(x, y))
				div.returnMouseFocus();
		};
		// handle mouse focus loss
		div.onMouseFocusLoss += () {
			if (this.manager)
				this.manager.removePanel(this);
		};
		// apply shanges to buttons
		foreach (Button btn; elements)
		{
			btn.onClick += () { div.returnMouseFocus(); };
			btn.htextAlign = HTextAlign.LEFT;
		}
		super(div);
	}

	/// Place the root div in such a way that it's left upper corner
	/// is preferably at 'luCorner', but can be moved in order to fit in windowSize.
	void placeByLUCorner(vec2i windowSize, vec2i luCorner)
	{
		vec2i pos = vec2i(
			min(windowSize.x - rootDiv.size.x, luCorner.x),
			min(windowSize.y - rootDiv.size.y, luCorner.y));
		rootDiv.position = pos;
	}

	/// Add this context menu to GuiManager and aquire mouse focus
	void activate(GuiManager mgr)
	{
		mgr.addPanel(this);
		rootDiv.requestMouseFocus();
	}
}


/// Build, place and activate the context menu on a gui manager
ContextMenu contextMenu(GuiManager mgr, Button[] elements,
	vec2i wndSize, vec2i luCorner, int rowHeight = 18)
{
	ContextMenu menu = new ContextMenu(elements, rowHeight);
	menu.placeByLUCorner(wndSize, luCorner);
	menu.activate(mgr);
	return menu;
}