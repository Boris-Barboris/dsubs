module dsubs_client.lib.fonts;

import std.string;

import derelict.sfml2.graphics;


__gshared sfFont*[string] g_loadedFonts;

__gshared immutable string[string] g_fontFiles;

shared static this()
{
	g_fontFiles = [
		"Sans": "fonts\\LiberationSans-Regular.ttf",
		"SansMono": "fonts\\LiberationMono-Regular.ttf",
	];
}

void loadGlobalFonts()
{
	foreach (string name, string filename; g_fontFiles)
	{
		auto cstr = toStringz(filename);
		g_loadedFonts[name] = sfFont_createFromFile(cstr);
	}
}
