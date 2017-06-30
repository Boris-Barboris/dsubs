module dsubs_client.gui.textbox;

import std.algorithm.comparison: min, max;
import std.conv: to;
import std.experimental.logger;
import std.string;
import std.math;
import std.utf;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_common.mutstring;

import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
public import dsubs_client.gui.element;
import dsubs_client.gui.fonts;
import dsubs_client.gui.manager;


__gshared float SCROLL_SPEED = 10.0f;

/// Multiline readonly scrollable field to show lot's of text on.
class TextBox: GuiElement
{
	protected
	{
		dstring _content;
		sfText*[] texts;
		// Special view to render texts. It's existence simplifies scrolling.
		sfView* text_view;
		uint _font_size = 12;
		string _fontname = "SansMono";
		sfColor _font_color = sfWhite;
		float _padding = 3.0f;

		// scrollbar will always be on the right, fuck it.
		// It will also always take space, but will simply be hidden
		// when not needed.
		// Let scrollbar line width be 1.0 for now.
		/*float _scrollbar_width = 15.0f;
		sfColor _scrollbar_line_color = sfWhite;
		sfColor _scrollbar_body_color = sfWhite;
		bool _scroll_visible = false;
		sfRectangleShape* scroll_rect_under;	// rails for scroll box
		sfRectangleShape* scroll_rect_over;		// scroll box itself
		*/
		float _scroll_position = 0.0f;
	}

	this(GuiManager manager)
	{
		super(manager);
		mouse_transparent = false;
		text_view = sfView_create();
		_content = ""d;
		onMouseScroll += &handle_mouse_scroll;
	}

	dstring content() { return _content; }

	// don't call it too often, it's heavy
	TextBox content(dstring val)
	{
		_content = val;
		_visuals_dirty = true;
		return this;
	}

	TextBox content(string val)
	{
		return content(toUTF32(val));
	}

	mixin ElementAccessor!(TextBox, uint, "font_size",
		"update_font_size(); _visuals_dirty = true;");

	mixin ElementAccessor!(TextBox, string, "fontname",
		"update_fontname(); _visuals_dirty = true;");

	mixin ElementAccessor!(TextBox, sfColor, "font_color",
		"update_font_color();");

	mixin ElementAccessor!(TextBox, float, "padding",
		"_visuals_dirty = true;");

	//mixin ElementAccessor!(TextBox, float, "scrollbar_width",
	//	"_visuals_dirty = true;");

	private void handle_mouse_scroll(GuiElement sender, int x, int y, int delta)
	{
		update_mouse_scroll(delta);
		update_text_view();
	}

	protected void update_mouse_scroll(int delta)
	{
		float max_scroll = (text_full_height - _size.y + 2.0f * _border_width);
		if (max_scroll <= 0.0f)
			_scroll_position = 0.0f;
		else
		{
			_scroll_position += SCROLL_SPEED * delta;
			_scroll_position = fmin(0.0f, fmax(_scroll_position, -max_scroll));
		}
	}

	// main text creation function
	protected void layout_text()
	{
		bool naiive_width = true;	// glyph width is initialized naively
		float glyph_width = get_glyph_width();
		float line_spacing = get_line_spacing();
		float line_width = _size.x - 2.0f * _padding - 2.0f * _border_width;// -_scrollbar_width;
		int chars_in_line = max(1, to!int(floor(line_width / glyph_width)));
		dchar[512] tmp = 0;		// stack-allocated array to hold processed line
		size_t content_idx = 0;	// cursor to query _content
		int line_idx = 0;
		size_t txt_idx = 0;		// cursor to query texts;
		size_t tmp_idx = 0;		// cursor to fill tmp

		void finalize_line()
		{
			if (tmp_idx == 0)
			{
				// it's an empty line, there's nothing to do
			}
			else
			{
				if (texts.length == txt_idx)
					create_text_obj();
				sfText* t = texts[txt_idx];
				txt_idx++;
				tmp[tmp_idx] = 0;	// zero terminator as if it was C string
				sfText_setUnicodeString(t, tmp.ptr);
				if (naiive_width)
				{
					// we now get accurate glyph width
					sfFloatRect bounds = sfText_getLocalBounds(t);
					glyph_width = bounds.width / tmp_idx;
					assert(glyph_width > 0.0f);
					chars_in_line = max(1, to!int(floor(line_width / glyph_width)));
					naiive_width = false;
					// go to start again
					txt_idx = tmp_idx = content_idx = 0;
					line_idx = 0;
					return;
				}
				setup_text_obj_coords(t, line_idx, line_spacing);
			}
			line_idx++;
			tmp_idx = 0;
		}

		while (content_idx < _content.length)
		{
			dchar symb = _content[content_idx];
			content_idx++;
			if (symb == '\n')
			{
				finalize_line();
				continue;
			}
			if (symb == '\t')
			{
				// replace tab with 4 spaces
				for (int i = 0; i < 4; i++)
				{
					tmp[tmp_idx] = ' ';
					tmp_idx++;
					if (tmp_idx == chars_in_line)
						finalize_line();
				}
			}
			else
			{
				tmp[tmp_idx] = symb;
				tmp_idx++;
				if (tmp_idx == chars_in_line)
					finalize_line();
			}
		}
		finalize_line();	// finalize the last line

		// we need to detroy unused sfText's:
		for (size_t i = txt_idx; i < texts.length; i++)
		{
			auto t = texts[i];
			sfText_destroy(t);
		}
		texts.length = txt_idx;

		// update scrolling parameters
		text_full_height = line_idx * line_spacing;
		update_mouse_scroll(0);
	}

	protected
	{
		float text_full_height = 0.0f;
	}

	private void create_text_obj()
	{
		sfText* t = sfText_create();
		sfText_setFont(t, loadedFonts[_fontname]);
		sfText_setCharacterSize(t, _font_size);
		sfText_setColor(t, _font_color);
		texts ~= t;
	}

	private void setup_text_obj_coords(sfText* t, int line_number, float interline)
	{
		sfFloatRect bounds = sfText_getLocalBounds(t);
		float x, y; // results
		x = -bounds.left;
		y = interline * line_number;
		sfText_setPosition(t, sfVector2f(round(x), round(y)));
	}

	float get_glyph_width()
	{
		// glyph of 'A'
		sfGlyph g = sfFont_getGlyph(loadedFonts[_fontname], 34, _font_size, false);
		return g.bounds.width;
	}

	float get_line_spacing()
	{
		return sfFont_getLineSpacing(loadedFonts[_fontname], _font_size);
	}

	override protected void update_viewport(Window wnd)
	{
		super.update_viewport(wnd);
		// and setup the viewport
		sfFloatRect vp;
		vp.left = round(_position.x + _border_width) / wnd.width;
		vp.top = round(_position.y + _border_width) / wnd.height;
		vp.width = round(_size.x - 2.0f * _border_width) / wnd.width;
		vp.height = round(_size.y - 2.0f * _border_width) / wnd.height;
		sfView_setViewport(text_view, vp);
	}

	override protected void update_view(Window wnd)
	{
		super.update_view(wnd);
		update_text_view();
	}

	protected void update_text_view()
	{
		// set coordinates of the view
		sfFloatRect coord;
		coord.left = round(-_padding);
		coord.top = round(-_padding - _scroll_position);
		coord.width = round(_size.x - 2.0f * _border_width);
		coord.height = round(_size.y - 2.0f * _border_width);
		sfView_reset(text_view, coord);
	}

	protected void update_font_size()
	{
		foreach (t; texts)
			sfText_setCharacterSize(t, _font_size);
	}

	protected void update_fontname()
	{
		foreach (t; texts)
			sfText_setFont(t, loadedFonts[_fontname]);
	}

	protected void update_font_color()
	{
		foreach (t; texts)
			sfText_setColor(t, _font_color);
	}

	override void update_visual(Window wnd)
	{
		layout_text();
		super.update_visual(wnd);
	}

	override protected void do_draw(Window wnd)
	{
		super.do_draw(wnd);
		sfRenderWindow_setView(wnd.ptr, text_view);
		// drawn texts line by line
		foreach (t; texts)
			sfRenderWindow_drawText(wnd.ptr, t, null);
	}
}

TextBox asTextBox(GuiElement el)
{
	return cast(TextBox) el;
}
