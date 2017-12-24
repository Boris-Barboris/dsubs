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
import dsubs_client.lib.fonts;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.element;


enum HTextAlign: ubyte
{
	LEFT = 0,
	CENTER = 1,
	RIGHT = 2,
}

enum VTextAlign: ubyte
{
	TOP = 0,
	CENTER = 1,
	BOTTOM = 2,
}

/// One text line
class Label: GuiElement
{
	private
	{
		uint m_fontSize = 12;
		string m_fontName = "SansMono";
		HTextAlign m_htextAlign = HTextAlign.CENTER;
		VTextAlign m_vtextAlign = VTextAlign.CENTER;
		int m_padding = 3;
	}

	protected
	{
		sfText* m_sfText;
		dmutstring m_content;
		sfColor m_fontColor = sfWhite;
	}

	this()
	{
		super();
		backgroundVisible = true;
		mouseTransparent = false;
		m_content = _s(""d, 31);
		initializeText();
	}

	~this()
	{
		sfText_destroy(m_sfText);
	}

	private void initializeText()
	{
		m_sfText = sfText_create();
		sfText_setFont(m_sfText, g_loadedFonts[m_fontName]);
		sfText_setCharacterSize(m_sfText, m_fontSize);
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		sfText_setColor(m_sfText, m_fontColor);
	}

	@property const(dmutstring) content() const { return m_content; }

	@property dmutstring content(dstring rhs)
	{
		str2mutCopy(rhs, m_content);
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
		return m_content;
	}

	@property dmutstring content(string rhs)
	{
		return content = toUTF32(rhs);
	}

	mixin GetSet!(uint, "fontSize",
		"sfText_setCharacterSize(m_sfText, rhs); updateText();");

	mixin GetSet!(string, "fontName",
		"sfText_setFont(m_sfText, g_loadedFonts[rhs]); updateText();");

	mixin GetSet!(sfColor, "fontColor",
		"sfText_setColor(m_sfText, rhs);");

	mixin FinalGetSet!(int, "padding", "updateText();");

	mixin FinalGetSet!(HTextAlign, "htextAlign", "updateText();");

	mixin FinalGetSet!(VTextAlign, "vtextAlign", "updateText();");

	protected
	{
		vec2i m_contentPos;	/// Estimated position of text first glyph.
		vec2i m_textPos;	/// Position of text sfml object
		float m_contentWidth = 0.0f;
		float m_contentHeight = 0.0f;
		int m_leftOffset;		// needed for textfield
	}

	// update text position
	protected void updateText()
	{
		sfFloatRect bounds = sfText_getLocalBounds(m_sfText);
		float x, y; // resultsing text element position
		final switch (m_htextAlign)
		{
			case HTextAlign.LEFT:
				x = m_padding - bounds.left + m_leftOffset;
				break;
			case HTextAlign.RIGHT:
				x = size.x - m_padding - bounds.left - bounds.width + m_leftOffset;
				break;
			case HTextAlign.CENTER:
				x = 0.5f * (size.x - 2.0f * bounds.left - bounds.width) + m_leftOffset;
		}
		m_contentPos.x = lrint(x + bounds.left).to!int;
		m_contentWidth = bounds.width;
		final switch (m_vtextAlign)
		{
			case VTextAlign.TOP:
				y = m_padding;
				break;
			case VTextAlign.BOTTOM:
				y = size.y - m_padding - m_fontSize * 1.25f;
				break;
			case VTextAlign.CENTER:
				y = 0.5f * (size.y - m_fontSize * 1.25f);
		}
		m_contentPos.y = lrint(y + bounds.top).to!int;
		m_contentHeight = 1.25f * m_fontSize;
		m_textPos.x = lrint(x).to!int;
		m_textPos.y = lrint(y).to!int;
		sfText_setPosition(m_sfText, m_textPos.tosf);
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		sfRenderWindow_drawText(wnd.wnd, m_sfText, &m_sfRst);
	}
}
