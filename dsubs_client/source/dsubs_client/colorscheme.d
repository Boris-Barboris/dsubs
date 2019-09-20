module dsubs_client.colorscheme;

import derelict.sfml2.graphics;


struct ColorScheme
{
	sfColor renderClear = sfColor(35, 31, 32, 255);
	sfColor defaultFont = sfWhite;
	sfColor textFieldBgnd = sfColor(57, 39, 44, 255);
	sfColor textFieldCursor = sfRed;
}

/// Global color scheme
ColorScheme COLORS;