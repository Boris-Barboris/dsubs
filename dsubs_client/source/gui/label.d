module dsubs_client.gui.label;

import std.string;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
import dsubs_client.gui.element;
import dsubs_client.gui.fonts;
import dsubs_client.gui.manager;


enum FontAlign: ubyte
{
	Left,
	Center,
	Right
}

class Label: GuiElement
{
	protected
	{
		string _content = "";
		sfText* text;
		uint _font_size = 12;
		string _fontname = "Sans";
		sfColor _font_color = sfWhite;
		FontAlign _horz_align = FontAlign.Center;
		FontAlign _vert_align = FontAlign.Center;	// left is top
		float _padding = 0.0f;	// used when align is not center
	}

	this(GuiManager manager)
	{
		super(manager);
	}

	protected void initialize_text()
	{
		text = sfText_create();
		sfText_setFont(text, loadedFonts[_fontname]);
		sfText_setCharacterSize(text, _font_size);
		sfText_setString(text, toStringz(_content));
		sfText_setColor(text, _font_color);
	}

	override void update_visual()
	{
		super.update_visual();
	}

	override void draw(Window wnd)
	{
		if (visible)
		{
			if (_visuals_dirty)
				update_visual();
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
			// draw actual text
		}
	}

}
