module dsubs_client.colorscheme;

import derelict.sfml2.graphics;


struct ColorScheme
{
	sfColor renderClear = sfColor(39, 34, 34, 255);
	sfColor defaultFont = sfWhite;
	sfColor textFieldBgnd = sfColor(64, 43, 43, 255);
	sfColor textFieldCursor = sfRed;
	sfColor simPanelBgnd = sfColor(10, 0, 0, 100);
	sfColor simButtonBgnd = sfColor(20, 14, 14, 200);
	sfColor simButtonDisabledBgnd = sfColor(255, 15, 15, 20);
	sfColor simButtonDisabledFont = sfColor(0, 0, 0, 40);
	sfColor simButtonSelectedStateBgnd = sfColor(86, 41, 41, 200);
	sfColor simLaunchButtonBgnd = sfColor(200, 50, 50, 255);
	sfColor simMessageFont = sfColor(189, 135, 135, 255);
}

/// Global color scheme
ColorScheme COLORS;