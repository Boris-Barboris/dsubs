module dsubs_client.gui.textfield;

import core.time;

import std.algorithm.comparison;
import std.conv;
import std.experimental.logger;
import std.math;
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
		cursor_rect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(rect, 0.0f);
		horz_align(TextAlign.LEFT);
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
		// x and y to local space
		x -= to!int(_position.x);
		y -= to!int(_position.y);
		// set cursor_start
		set_cursor_from_coords(cursor_start, x, y);
		cursor_end = cursor_start;
		update_cursor_visuals();
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
			// x and y to local space
			x -= to!int(_position.x);
			y -= to!int(_position.y);
			// set cursor_start
			int old_curs_end = cursor_end;
			set_cursor_from_coords(cursor_end, x, y);
			if (old_curs_end != cursor_end)
				update_cursor_visuals();
		}
	}

	// set cursor to position according to
	void set_cursor_from_coords(ref int cursor, int x, int y)
	{
		float char_width;
		if (_content.length <= 1)
		{
			cursor = 0;
			return;
		}
		else
			char_width = content_width / (_content.length - 1);
		int index = max(0,
			min(_content.length - 1,
				to!int(round((x - content_left) / char_width))));
		cursor = index;
	}

	override void handleKbFocusLoss()
	{
		super.handleKbFocusLoss();
		cursor_start = cursor_end = 0;
	}

	override void update_visual(Window wnd)
	{
		// TODO: remove if not needed
		super.update_visual(wnd);
		//update_cursor_visuals();
	}

	override void update_text_position()
	{
		super.update_text_position();
		// safety check for cursors
		if (_content.length <= cursor_start)
			cursor_start = _content.length - 1;
		if (_content.length <= cursor_end)
			cursor_end = _content.length - 1;
		update_cursor_visuals();
	}

	void update_cursor_visuals()
	{
		float char_width;
		if (_content.length <= 1)
			char_width = 0.0f;
		else
			char_width = content_width / (_content.length - 1);
		// position
		sfRectangleShape_setPosition(cursor_rect,
			sfVector2f(
				content_left + char_width * cursor_start,
				content_top));
		// size
		float cursor_width = 2.0f;
		if (cursor_end != cursor_start)
			cursor_width = char_width * (cursor_end - cursor_start);
		sfRectangleShape_setSize(cursor_rect,
			sfVector2f(cursor_width, content_height));
		sfRectangleShape_setFillColor(cursor_rect, _cursor_color);
		blink_state = true;
	}

	private uint counter = 0;
	private bool blink_state = true;
	static uint BLINK_FREQ = 15;

	override void do_draw(Window wnd)
	{
		this.GuiElement.do_draw(wnd);	// draw background rectangle
		// now we're in local space because of viewport
		if (kb_focused || mouse_focused)
		{
			if (cursor_start == cursor_end)
			{
				// we have no text selected, display blinking caret
				counter++;
				if (counter % BLINK_FREQ == 0)
					blink_state = !blink_state;
				if (blink_state)
					sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
			}
			else
				sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
		}
		// text is drawn over cursor
		sfRenderWindow_drawText(wnd.ptr, text, null);
	}

	void do_handle_text(dchar c)
	{
		// first we check wether we had range of symbols selected
		if (cursor_start == cursor_end)
		{
			// it's just a caret
			switch (c)
			{
				case '\b':	// backspace
					if (_content.length > 1 && cursor_start > 0)
					{
						_content.remove_at(cursor_start - 1);
						cursor_start = cursor_end = cursor_start - 1;
					}
					break;
				default:
					log("captured unicode symbol ", to!uint(c));
					_content.insert_at(c, cursor_start);
					cursor_start = cursor_end = cursor_start + 1;
					break;
			}
		}
		else
		{
			// range is selected
			int ordered_start = min(cursor_start, cursor_end);
			int ordered_end = max(cursor_start, cursor_end);
			switch (c)
			{
				case '\b':	// backspace
					_content.remove_interval(ordered_start, ordered_end - 1);
					cursor_start = cursor_end = ordered_start;
					break;
				default:
					log("captured unicode symbol ", to!uint(c));
					_content.remove_interval(ordered_start, ordered_end - 1);
					_content.insert_at(c, ordered_start);
					cursor_start = cursor_end = ordered_start + 1;
					break;
			}
		}
		// update sfml text
		sfText_setUnicodeString(text, _content.ptr);
		update_text_position();
	}

	override HandleResult handleKeyboard(const sfEvent* evt)
	{
		if (!this.active)
		{
			returnKbFocus();
			return HandleResult(true);
		}
		// TODO: handle DELETE keyboard key and arrow keys
		if (evt.type == sfEvtKeyPressed)
		{
			sfKeyEvent kevt = evt.key;
			switch (kevt.code)
			{
				case sfKeyLeft:
					if (kevt.shift)
						cursor_end = max(0, cursor_end - 1);
					else
					{
						cursor_start = max(0, cursor_start - 1);
						cursor_end = cursor_start;
					}
					update_cursor_visuals();
					break;
				case sfKeyRight:
					if (kevt.shift)
						cursor_end = min(_content.length - 1, cursor_end + 1);
					else
					{
						cursor_start = min(_content.length - 1, cursor_start + 1);
						cursor_end = cursor_start;
					}
					update_cursor_visuals();
					break;
				case sfKeyHome:
					if (kevt.shift)
						cursor_end = 0;
					else
						cursor_start = cursor_end = 0;
					update_cursor_visuals();
					break;
				case sfKeyEnd:
					if (kevt.shift)
						cursor_end = _content.length - 1;
					else
						cursor_start = cursor_end = _content.length - 1;
					update_cursor_visuals();
					break;
				case sfKeyA:
					if (kevt.control)
					{
						cursor_start = 0;
						cursor_end = _content.length - 1;
						update_cursor_visuals();
					}
					break;
				case sfKeyDelete:
					if (cursor_start == cursor_end)
					{
						if (cursor_start < _content.length - 1)
							_content.remove_at(cursor_start);
					}
					else
					{
						int ordered_start = min(cursor_start, cursor_end);
						int ordered_end = max(cursor_start, cursor_end);
						_content.remove_interval(ordered_start, ordered_end - 1);
						cursor_start = cursor_end = ordered_start;
					}
					// update sfml text
					sfText_setUnicodeString(text, _content.ptr);
					update_text_position();
					break;
				default:
					break;
			}
			return HandleResult(false);
		}
		if (evt.type == sfEvtTextEntered)
		{
			dchar c = evt.text.unicode;
			switch (c)
			{
				case '\r':
					// do nothing
					break;
				case '\n':
					// do nothing
					break;
				case '\t':
					// do nothing
					break;
				case 27:
					// ESC character
					returnKbFocus();
					break;
				default:
					if (c >= 32 || c == '\b')
						do_handle_text(c);
			}
			return HandleResult(false);
		}
		return HandleResult(true);
	}
}

Label asTextField(GuiElement el)
{
	return cast(TextField) el;
}
