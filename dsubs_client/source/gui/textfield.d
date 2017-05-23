module dsubs_client.gui.textfield;

import core.time;

import std.conv;
import std.string;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.sfml;
import dsubs_client.gui.label;
import dsubs_client.gui.manager;


class TextField: label
{
	protected
	{
		sfColor _cursor_color = sfRed;
		sfRectangleShape* cursor_rect;
		int cursor_start = 0;
		int cursor_end = 0;		// first character after the cursor
	}

	this(GuiManager manager)
	{
		super(manager);
		border_width(1.0f);
		backgroud_color(sfColor(50, 28, 28, 150));
		horz_align(TextAlign.LEFT);
		cursor_rect = sfRectangleShape_create();
		onMouseDown += &handle_mouse_down;
		onMouseUp += &handle_mouse_up;
		onMouseMove += &handle_mouse_move;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "cursor_color",
		"_visuals_dirty = true;");

	protected void handle_mouse_down(GuiElement s, int x, int y, sfMouseButton btn)
	{
		returnKbFocus();
		// first we capture mouse in order to handle text selection
		requestMouseFocus();
	}

	protected void handle_mouse_up(GuiElement s, int x, int y, sfMouseButton btn)
	{
		// give mouse focus back
		returnMouseFocus();
		// capture keyboard
		requestKbFocus();
	}

	protected void handle_mouse_move(GuiElement s, int x, int y)
	{
		if (mouse_focused)
		{
			// we have mouse captured, we need to update cursor
		}
	}

	override void update_visual()
	{
		super.update_visual();
		update_cursor_position();
	}

	void update_cursor_position()
	{

	}

	override void draw(Window wnd)
	{
		// TODO: setup viewport
		this.GuiElement.draw(wnd);
		if (kb_focused)
		{
			// we're focused, so we need to display our cursor
			sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
		}
		// text is drawn over cursor
		sfRenderWindow_drawText(wnd.ptr, text, null);
	}

	override HandleResult handleKeyboard(const sfEvent* evt)
	{
		if (!this.active)
		{
			returnKbFocus();
			return HandleResult(true);
		}
		if (evt.type == sfEvtTextEntered)
		{
			// TODO: handle text here
			return HandleResult(false);
		}
		return HandleResult(true);
	}
}

Label asTextField(GuiElement el)
{
	return cast(TextField) el;
}
