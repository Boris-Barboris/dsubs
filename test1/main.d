import std.stdio;

import derelict.sfml2.system; // For the system library.
import derelict.sfml2.window; // For the window library.
import derelict.sfml2.audio; // For the audio library.
import derelict.sfml2.graphics; // For the graphics library.
import derelict.sfml2.network; // For the network library.

int main(string[] argv)
{
	// Load the SFML2 System libraries you need. Note that this sample imports
    // and loads them all, but you only need to do so for the libraries you intend
    // to actually use.
    DerelictSFML2System.load();
    DerelictSFML2Window.load();
    DerelictSFML2Audio.load();
    DerelictSFML2Graphics.load();
    DerelictSFML2Network.load();

	// simple window code
	sfVideoMode video_mode = sfVideoMode(800, 600, 32);
	sfContextSettings context_set = sfContextSettings(
		0, 0, 4, 3, 0, sfContextDefault);
	sfRenderWindow *window = sfRenderWindow_create(
		video_mode, "app1", sfDefaultStyle, &context_set);
	sfWindow* base_window = cast(sfWindow*)window;

	sfEvent cur_event;

	while (true)
	{
		if (sfWindow_pollEvent(base_window, &cur_event))
		{
			if (cur_event.type == sfEvtClosed)
				break;
		}
		sfRenderWindow_clear(window, sfColor(25, 25, 25, 0));
		sfRenderWindow_display(window);
	}

    writeln("Close event!");
    return 0;
}
