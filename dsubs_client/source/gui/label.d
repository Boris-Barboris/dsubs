module dsubs_client.gui.label;

import std.conv;
import std.string;
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


enum TextAlign: ubyte
{
	LEFT,
	CENTER,
	RIGHT
}

class Label: GuiElement
{
	protected
	{
		dmutstring _content;
		sfText* text;
		uint _font_size = 12;
		string _fontname = "SansMono";
		sfColor _font_color = sfWhite;
		TextAlign _horz_align = TextAlign.CENTER;
		TextAlign _vert_align = TextAlign.CENTER;	// left is top
		float _padding = 2.0f;		// used when align is not center
	}

	this(GuiManager manager)
	{
		super(manager);
		mouse_transparent = false;
		_content = _s(""d, 31);
		initialize_text();
	}

	protected void initialize_text()
	{
		text = sfText_create();
		load_fonts();
		sfText_setFont(text, loadedFonts[_fontname]);
		sfText_setCharacterSize(text, _font_size);
		sfText_setUnicodeString(text, _content.ptr);
		sfText_setColor(text, _font_color);
	}

	const(dmutstring) content() { return _content; }

	Label content(dstring val)
	{
		str2mut_copy(val, _content);
		sfText_setUnicodeString(text, _content.ptr);
		update_text_position();
		return this;
	}

	Label content(string val)
	{
		return content(toUTF32(val));
	}

	mixin ElementAccessor!(Label, uint, "font_size",
		"sfText_setCharacterSize(text, _font_size); update_text_position();");

	mixin ElementAccessor!(Label, string, "fontname",
		"sfText_setFont(text, loadedFonts[_fontname]); update_text_position();");

	mixin ElementAccessor!(Label, sfColor, "font_color",
		"sfText_setColor(text, _font_color);");

	mixin ElementAccessor!(Label, float, "padding",
		"update_text_position();");

	mixin ElementAccessor!(Label, TextAlign, "horz_align",
		"update_text_position();");

	mixin ElementAccessor!(Label, TextAlign, "vert_align",
		"update_text_position();");

	override void update_visual(Window wnd)
	{
		super.update_visual(wnd);
		update_text_position();
	}

	protected
	{
		// text content visual parameters they way they look
		int content_left;
		int content_top;
		float content_width;
		float content_height;
		int content_x, content_y;
	}

	void update_text_position()
	{
		sfFloatRect bounds = sfText_getLocalBounds(text);
		float x, y; // results
		final switch (_horz_align)
		{
			case TextAlign.LEFT:
				x = _padding - bounds.left;
				break;
			case TextAlign.RIGHT:
				x = _size.x - _padding - bounds.left - bounds.width;
				break;
			case TextAlign.CENTER:
				x = 0.5f * (_size.x - 2.0f * bounds.left - bounds.width);
		}
		content_left = to!int(x + bounds.left);
		content_width = bounds.width;
		final switch (_vert_align)
		{
			case TextAlign.LEFT:
				//y = _padding - bounds.top;
				y = _padding;
				break;
			case TextAlign.RIGHT:
				//y = _size.y - _padding - bounds.top - bounds.height;
				y = _size.y - _padding - _font_size * 1.25f;
				break;
			case TextAlign.CENTER:
				//y = 0.5f * (_size.y - 2.0f * bounds.top - bounds.height);
				y = 0.5f * (_size.y - _font_size * 1.25f);
		}
		content_top = to!int(y);	// stable
		content_height = 1.25f * _font_size;	// stable as well
		sfText_setPosition(text, sfVector2f(to!int(x), to!int(y)));
	}

	override void do_draw(Window wnd)
	{
		super.do_draw(wnd);
		// draw actual text
		sfRenderWindow_drawText(wnd.ptr, text, null);
	}
}

Label asLabel(GuiElement el)
{
	return cast(Label) el;
}
