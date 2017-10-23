module dsubs_client.gui.textfield;

import std.algorithm.comparison;
import std.conv;
import std.experimental.logger;
import std.math;
import std.string;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.lib.sfml;
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
		backgroud_color(sfColor(50, 28, 28, 150));
		cursor_rect = sfRectangleShape_create();
		sfRectangleShape_setFillColor(cursor_rect, _cursor_color);
		sfRectangleShape_setOutlineThickness(rect, 0.0f);
		horz_align(TextAlign.LEFT);
		onMouseDown += &handle_mouse_down;
		onMouseUp += &handle_mouse_up;
		onMouseMove += &handle_mouse_move;
		onKeyPressed += &hande_KeyPressed;
		onTextEntered += &handle_TextEntered;
		onMouseScroll += &handle_MouseScroll;
	}

	mixin ElementAccessor!(TextField, sfColor, "cursor_color",
		"sfRectangleShape_setFillColor(cursor_rect, _cursor_color);");

	protected void handle_mouse_down(GuiElement s, int x, int y, sfMouseButton btn)
	{
		returnKbFocus();
		// first we capture mouse in order to handle text selection
		requestMouseFocus();
		// x and y to local space
		x -= _position.x;
		y -= _position.y;
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
			x -= _position.x;
			y -= _position.y;
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
				to!int(lrint((x - content_left) / char_width))));
		cursor = index;
	}

	override void handleKbFocusLoss()
	{
		super.handleKbFocusLoss();
		cursor_start = cursor_end = 0;
	}

	override void update_text()
	{
		super.update_text();
		// safety check for cursors
		if (_content.length <= cursor_start)
			cursor_start = _content.length - 1;
		if (_content.length <= cursor_end)
			cursor_end = _content.length - 1;
		update_cursor_visuals();
	}

	protected bool update_recurs = false;

	protected void update_cursor_visuals()
	{
		float char_width;
		if (_content.length <= 1)
		{
			char_width = 0.0f;
			_left_offset = 0.0f;
		}
		else
			char_width = content_width / (_content.length - 1);
		// position of cursor_start
		float start_x = content_left + char_width * cursor_start;
		// position of cursor_end
		float end_x = start_x + char_width * (cursor_end - cursor_start);
		if (_content.length > 1 && !update_recurs)
		{
			// make sure cursor_end is always visible and is located inside
			// element's rectangle
			bool reupdate_visuals = false;
			if (end_x < _padding)
			{
				// we need to move text right
				_left_offset = min(0.0f, _left_offset - end_x + _padding + 1.0f);
				reupdate_visuals = true;
			}
			else if (end_x > _size.x - _padding)
			{
				// we need to move text left
				_left_offset -= (end_x - _size.x + 1.0f + _padding);
				reupdate_visuals = true;
			}
			if (reupdate_visuals)
			{
				// we need to shift the text, let's use recursion
				super.update_text_position();
				update_recurs = true;
				update_cursor_visuals();
				update_recurs = false;
				return;
			}
		}
		// cursor_rect width
		float cursor_width = 2.0f;
		if (cursor_end != cursor_start)
			cursor_width = end_x - start_x;
		sfRectangleShape_setPosition(cursor_rect,
			sfVector2f(
				start_x + _position.x,
				content_top + _position.y));
		sfRectangleShape_setSize(cursor_rect,
			sfVector2f(cursor_width, content_height));
		blink_state = true;
	}

	private uint blink_counter = 0;
	private bool blink_state = true;
	static int BLINK_FREQ = 15;

	override protected void draw_contents(Window wnd)
	{
		// now we're in local space because of viewport
		if (kb_focused || mouse_focused)
		{
			if (cursor_start == cursor_end)
			{
				// we have no text selected, display blinking caret
				blink_counter++;	// framerate-dependent, but i don't really care
				if (blink_counter % BLINK_FREQ == 0)
					blink_state = !blink_state;
				if (blink_state)
					sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
			}
			else
				sfRenderWindow_drawRectangleShape(wnd.ptr, cursor_rect, null);
		}
		// text is drawn over cursor
		super.draw_contents(wnd);
	}

	protected void insert_at(dchar c, size_t idx)
	{
		_content.insert_at(c, idx);
	}

	protected void remove_at(size_t idx)
	{
		_content.remove_at(idx);
	}

	protected void remove_interval(size_t start, size_t end)
	{
		_content.remove_interval(start, end);
	}

	// function to filter entered symbols by. Should return true if
	// symbol is acceptable, otherwise false.
	bool function(dchar) symbol_filter;

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
						remove_at(cursor_start - 1);
						cursor_start = cursor_end = cursor_start - 1;
					}
					break;
				default:
					log("captured unicode symbol ", to!uint(c));
					if (symbol_filter && !symbol_filter(c))
					{
						log("ignored by filter");
						return;
					}
					insert_at(c, cursor_start);
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
					remove_interval(ordered_start, ordered_end - 1);
					cursor_start = cursor_end = ordered_start;
					break;
				default:
					log("captured unicode symbol ", to!uint(c));
					if (symbol_filter && !symbol_filter(c))
					{
						log("ignored by filter");
						return;
					}
					remove_interval(ordered_start, ordered_end - 1);
					insert_at(c, ordered_start);
					cursor_start = cursor_end = ordered_start + 1;
					break;
			}
		}
		// update sfml text
		sfText_setUnicodeString(text, _content.ptr);
		update_text_position();
	}

	void handle_MouseScroll(GuiElement sender, int x, int y, int delta)
	{
		if (kb_focused && !mouse_focused)
		{
			cursor_start = max(0, min(_content.length - 1, cursor_start + delta));
			cursor_end = cursor_start;
			update_cursor_visuals();
		}
	}

	void hande_KeyPressed(GuiElement sender, const sfKeyEvent* kevt)
	{
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
						remove_at(cursor_start);
				}
				else
				{
					int ordered_start = min(cursor_start, cursor_end);
					int ordered_end = max(cursor_start, cursor_end);
					remove_interval(ordered_start, ordered_end - 1);
					cursor_start = cursor_end = ordered_start;
				}
				// update sfml text
				sfText_setUnicodeString(text, _content.ptr);
				update_text_position();
				break;
			case sfKeyReturn:
				// we interpret enter as desire to commit changes and return
				// keyboard focus
				returnKbFocus();
				break;
			default:
				break;
		}
	}

	void handle_TextEntered(GuiElement sender, const sfTextEvent* evt)
	{
		dchar c = evt.unicode;
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
	}
}

TextField asTextField(GuiElement el)
{
	return cast(TextField) el;
}
