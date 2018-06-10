module dsubs_client.lib.fonts;

import std.string;
import std.container.rbtree;

import derelict.sfml2.graphics;

import gfm.math.vector: vec4i;

import dsubs_client.lib.sfml;


struct FontGlyphParams
{
	int fontSize;	/// font size this params are measured for
	/// if text is placed on x1 and first text pixel is on x2, this is x2 - x1
	int leftOffset;
	/// if text is placed on y1 and first text pixel is on y2, this is y2 - y1
	int topOffset;
	/// actual height of test string
	int actualHeight;
}

/// Font object and it's metadata
struct FontRecord
{
	sfFont* ptr;

	// cache for different font sizes
	private alias RbType = RedBlackTree!(FontGlyphParams, "a.fontSize < b.fontSize");
	private RbType m_glyphParams = new RbType();

	FontGlyphParams glyphParams(int fontSize)
	{
		assert(fontSize > 0);
		auto existingRec = m_glyphParams.equalRange(FontGlyphParams(fontSize));
		if (existingRec.empty)
		{
			auto newRec = runTrial(fontSize);
			m_glyphParams.insert(newRec);
			return newRec;
		}
		return existingRec.front();
	}

	private FontGlyphParams runTrial(int fontSize)
	{
		static dstring g_testStr = "AIjgyl\0"d;
		sfText* text = sfText_create();
		scope(exit) sfText_destroy(text);
		sfText_setFont(text, ptr);
		sfText_setCharacterSize(text, fontSize);
		sfText_setUnicodeString(text, g_testStr.ptr);
		vec4i bounds = sfText_getLocalBounds(text).round;
		return FontGlyphParams(fontSize, bounds[0], bounds[1], bounds[3]);
	}
}

__gshared FontRecord*[string] g_loadedFonts;

__gshared immutable string[string] g_fontFiles;

shared static this()
{
	g_fontFiles = [
		"Sans": "fonts/LiberationSans-Regular.ttf",
		"SansMono": "fonts/LiberationMono-Regular.ttf",
		"UbuntuMono": "fonts/ubuntu.mono.ttf",
	];
}

void loadGlobalFonts()
{
	foreach (string name, string filename; g_fontFiles)
	{
		auto cstr = toStringz(filename);
		g_loadedFonts[name] = new FontRecord(sfFont_createFromFile(cstr));
	}
}
