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


/// Multiline readonly scrollable field to show lot's of text on.
class TextBox: GuiElement
{
	protected
	{
		dstring _content;
		sfText*[] texts;
		uint _font_size = 12;
		string _fontname = "SansMono";
		sfColor _font_color = sfWhite;
		float _padding = 3.0f;
	}

	this(GuiManager manager)
	{
		super(manager);
		_sizeType = SizeType.CONTENT;
		mouse_transparent = false;
		_content = ""d;
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

	mixin SuperAccessor!(TextBox, SizeType, "sizeType",
		"if (val != SizeType.CONTENT) assert(0, \"TextBox always has CONTENT sizeType\");");

	mixin ElementAccessor!(TextBox, uint, "font_size",
		"update_font_size(); _visuals_dirty = true;");

	mixin ElementAccessor!(TextBox, string, "fontname",
		"update_fontname(); _visuals_dirty = true;");

	mixin ElementAccessor!(TextBox, sfColor, "font_color",
		"update_font_color();");

	mixin ElementAccessor!(TextBox, float, "padding",
		"_visuals_dirty = true;");

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
					chars_in_line = max(1, to!int(floor(line_width / glyph_width)) - 1);
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

		text_full_height = line_idx * line_spacing;
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
		x = -bounds.left + _padding + _border_width;
		y = interline * line_number + _padding + _border_width;
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

	override void update_visual()
	{
		layout_text();
		// now we set height according to text dimensions
		size(vec2f(_size.x, 2.0f * _padding + 2.0 * _border_width + text_full_height));
		super.update_visual();
	}

	override protected void do_draw(Window wnd)
	{
		super.do_draw(wnd);
		//sfRenderWindow_setView(wnd.ptr, text_view);
		// drawn texts line by line
		foreach (t; texts)
			sfRenderWindow_drawText(wnd.ptr, t, null);
	}
}

TextBox asTextBox(GuiElement el)
{
	return cast(TextBox) el;
}
