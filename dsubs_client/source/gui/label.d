module dsubs_client.gui.label;

import std.conv;
import std.string;

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
		mutstring _content;
		sfText* text;
		uint _font_size = 12;
		string _fontname = "SansMono";
		sfColor _font_color = sfWhite;
		TextAlign _horz_align = TextAlign.CENTER;
		TextAlign _vert_align = TextAlign.CENTER;	// left is top
		float _padding = 1.0f;		// used when align is not center
	}

	this(GuiManager manager)
	{
		super(manager);
		_content = _s("", 63);
		initialize_text();
	}

	protected void initialize_text()
	{
		text = sfText_create();
		load_fonts();
		sfText_setFont(text, loadedFonts[_fontname]);
		sfText_setCharacterSize(text, _font_size);
		sfText_setString(text, toStringz(_content));
		sfText_setColor(text, _font_color);
	}

	mutstring content() { return _content; }

	Label content(string val)
	{
		str2mut_copy(val, _content);
		sfText_setString(text, _content.ptr);
		update_text_position();
		return this;
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

	override void update_visual()
	{
		super.update_visual();
		update_text_position();
	}

	void update_text_position()
	{
		sfFloatRect bounds = sfText_getLocalBounds(text);
		float x, y; // results
		final switch (_horz_align)
		{
			case TextAlign.LEFT:
				x = _position.x + _padding;
				break;
			case TextAlign.RIGHT:
				x = _position.x + _size.x - _padding - bounds.left - bounds.width;
				break;
			case TextAlign.CENTER:
				x = _position.x + 0.5f * (_size.x - bounds.left - bounds.width);
		}
		final switch (_vert_align)
		{
			case TextAlign.LEFT:
				y = _position.y + _padding;
				break;
			case TextAlign.RIGHT:
				y = _position.y + _size.y - _padding - bounds.top - bounds.height;
				break;
			case TextAlign.CENTER:
				y = _position.y + 0.5f * (_size.y - bounds.top - bounds.height);
		}
		sfText_setPosition(text, sfVector2f(to!int(x), to!int(y)));
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		if (visible)
		{
			// draw actual text
			sfRenderWindow_drawText(wnd.ptr, text, null);
		}
	}
}

Label asLabel(GuiElement el)
{
	return cast(Label) el;
}
