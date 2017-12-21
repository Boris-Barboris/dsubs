module dsubs_client.gui.label;

import std.conv;
import std.string;
import std.math;
import std.utf;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_common.mutstring;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.gui.element;
import dsubs_client.gui.fonts;


/// self-explanatory for horizontal, left is top for vertical align
enum TextAlign: ubyte
{
	LEFT = 0,
	TOP = 0,
	CENTER = 1,
	RIGHT = 2,
	BOTTOM = 2
}

/// One text line
class Label: GuiElement
{
	private
	{
		dmutstring m_content;
		uint _font_size = 12;
		string _fontname = "SansMono";
		sfColor _font_color = sfWhite;
		TextAlign _horz_align = TextAlign.CENTER;
		TextAlign _vert_align = TextAlign.CENTER;	// left is top
	}

	protected
	{
		sfText* text;
		int _padding = 3;		// used when align is not center
	}

	this()
	{
		super();
		mouse_transparent = false;
		_content = _s(""d, 31);
		initialize_text();
	}

	~this()
	{
		sfText_destroy(text);
	}

	private final void initialize_text()
	{
		text = sfText_create();
		sfText_setFont(text, g_loadedFonts[_fontname]);
		sfText_setCharacterSize(text, _font_size);
		sfText_setUnicodeString(text, _content.ptr);
		sfText_setColor(text, _font_color);
	}

	@property const(dmutstring) content() const { return _content; }

	Label content(dstring val)
	{
		str2mut_copy(val, _content);
		sfText_setUnicodeString(text, _content.ptr);
		update_text();
		return this;
	}

	final Label content(string val)
	{
		return content(toUTF32(val));
	}

	mixin ElementAccessor!(Label, uint, "font_size",
		"sfText_setCharacterSize(text, _font_size); update_text();");

	mixin ElementAccessor!(Label, string, "fontname",
		"sfText_setFont(text, g_loadedFonts[_fontname]); update_text();");

	mixin ElementAccessor!(Label, sfColor, "font_color",
		"sfText_setColor(text, _font_color);");

	mixin ElementAccessor!(Label, int, "padding", "update_text();");

	mixin ElementAccessor!(Label, TextAlign, "horz_align", "update_text();");

	mixin ElementAccessor!(Label, TextAlign, "vert_align", "update_text();");

	protected
	{
		// text content visual parameters they way they look
		int content_left;	// relative offsets
		int content_top;
		float content_width = 0.0f;
		float content_height = 0.0f;
		int left_offset = 0.0;		// needed for textfield
	}

	protected void update_text()
	{
		sfFloatRect bounds = sfText_getLocalBounds(text);
		float x, y; // results
		final switch (_horz_align)
		{
			case TextAlign.LEFT:
				x = _padding - bounds.left + left_offset;
				break;
			case TextAlign.RIGHT:
				x = get_size.x - _padding - bounds.left - bounds.width + left_offset;
				break;
			case TextAlign.CENTER:
				x = 0.5f * (get_size.x - 2.0f * bounds.left - bounds.width) + left_offset;
		}
		content_left = cast(int)lrint(x + bounds.left);
		content_width = bounds.width;
		final switch (_vert_align)
		{
			case TextAlign.LEFT:
				//y = _padding - bounds.top;
				y = _padding;
				break;
			case TextAlign.RIGHT:
				//y = get_size.y - _padding - bounds.top - bounds.height;
				y = get_size.y - _padding - _font_size * 1.25f;
				break;
			case TextAlign.CENTER:
				//y = 0.5f * (_size.y - 2.0f * bounds.top - bounds.height);
				y = 0.5f * (get_size.y - _font_size * 1.25f);
		}
		content_top = cast(int)lrint(y);		// just werks
		content_height = 1.25f * _font_size;	// just werks
		sfText_setPosition(text,
			sfVector2f(content_left, content_top));
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		sfRenderWindow_drawText(wnd.ptr, text, &sf_rst);
	}
}

Label asLabel(GuiElement el)
{
	return cast(Label) el;
}
