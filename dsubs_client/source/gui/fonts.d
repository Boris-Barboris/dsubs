module dsubs_client.gui.fonts;

import std.string;

import derelict.sfml2.graphics;


__gshared sfFont*[string] loadedFonts;

immutable string[string] font_files;

static this()
{
	font_files = [
		"Sans": "fonts/LiberationSans-Regular.ttf",
		"SansMono": "fonts/LiberationMono-Regular.ttf",
	];
}

__gshared bool _fonts_loaded = false;

void load_fonts()
{
	if (_fonts_loaded)
		return;
	foreach (string name, string filename; font_files)
	{
		auto cstr = toStringz(filename);
		sfFont* font = sfFont_createFromFile(cstr);
		loadedFonts[name] = font;
	}
	_fonts_loaded = true;
}
