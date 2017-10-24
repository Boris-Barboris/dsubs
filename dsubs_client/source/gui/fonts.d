module dsubs_client.gui.fonts;

import std.string;

import derelict.sfml2.graphics;


__gshared sfFont*[string] g_loadedFonts;

__gshared immutable string[string] g_font_files;

static shared this()
{
	g_font_files = [
		"Sans": "fonts/LiberationSans-Regular.ttf",
		"SansMono": "fonts/LiberationMono-Regular.ttf",
	];
	foreach (string name, string filename; g_font_files)
	{
		auto cstr = toStringz(filename);
		sfFont* font = sfFont_createFromFile(cstr);
		g_loadedFonts[name] = font;
	}
}
