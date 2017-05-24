module dsubs_client.gui.textfield;

import core.time;

import std.conv;
import std.string;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.gui.label;
import dsubs_client.gui.manager;


class TextField: Label
{
	protected
	{
		sfColor _cursor_color = sfRed;
		sfRectangleShape* cursor_rect;
		int cursor_start = 0;	// start of selection
		int cursor_end = 0;		// first character after the selection
	}

	this(GuiManager manager)
	{
		super(manager);
		// larger buffer capacity
		_content.reserve(64);
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

	override void handleKbFocusLoss()
	{
		super.handleKbFocusLoss();
		cursor_start = cursor_end = 0;
	}

	override void update_visual(Window wnd)
	{
		super.update_visual(wnd);
		update_cursor_position();
	}

	void update_cursor_position()
	{

	}

	private uint counter = 0;
	private bool blink_state = true;
	static uint BLINK_FREQ = 30;

	override void do_draw(Window wnd)
	{
		this.GuiElement.do_draw(wnd);	// draw background rectangle
		// now we're in local space because of viewport
		if (kb_focused)
		{
			if (cursor_start == cursor_end)
			{
				// we have no text selected, display blinking caret
				counter++;
				if (counter % BLINK_FREQ == 0)
					blink_state = !blink_state;
				//if (blink_state)
				//	sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
			}
			else
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
			// first we check wether we had range of symbols selected
			if (cursor_start == cursor_end)
			{
				// we don't, it's just a caret
				dchar c = evt.text.unicode;
				_content.insert_at(c, cursor_start);
				// move caret forward
				cursor_start = cursor_end = cursor_start + 1;
			}
			// update sfml text
			sfText_setUnicodeString(text, _content.ptr);
			update_text_position();
			return HandleResult(false);
		}
		return HandleResult(true);
	}
}

Label asTextField(GuiElement el)
{
	return cast(TextField) el;
}
