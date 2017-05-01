module dsubs_client.gui.button;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.event;
import dsubs_client.core.window;
public import dsubs_client.gui.label;
import dsubs_client.gui.manager;


enum ButtonType: ubyte
{
	SYNC,		// onclick event is synchronous, instant return to unpressed state
	ASYNC,		// onclick event is asynchronous, unpressed after
				// callback was called from the outside
	TOGGLE		// synchronous toggle
}

class Button: Label
{
	protected
	{
		ButtonType _buttonType;
		sfColor _pressed_color = sfRed;
		sfColor _released_color = sfWhite;
		bool _pressed;
	}

	this(GuiManager manager)
	{
		super(manager);
		update_font_color();
		onMouseDown += &handle_mouse_down;
		onMouseUp += &handle_mouse_up;
	}

	mixin ElementAccessor!(Button, ButtonType, "buttonType", "");
	mixin ElementAccessor!(Button, sfColor, "pressed_color", "update_font_color();");
	mixin ElementAccessor!(Button, sfColor, "released_color", "update_font_color();");

	mixin OverrideAccessor!(Button, sfColor, "font_color",
		"released_color(val);");

	bool pressed() { return _pressed; }

	protected void update_font_color()
	{
		if (_pressed)
			sfText_setColor(text, _pressed_color);
		else
			sfText_setColor(text, _released_color);
	}

	protected void handle_mouse_down(GuiElement s, int x, int y, sfMouseButton btn)
	{
		if (_buttonType == ButtonType.TOGGLE)
		{
			_pressed = !_pressed;
			update_font_color();
		}
		else if (!_pressed)
		{
			_pressed = true;
			update_font_color();
		}
	}

	protected void handle_mouse_up(GuiElement s, int x, int y, sfMouseButton btn)
	{
		if (_buttonType == ButtonType.TOGGLE)
			onClick(this, btn);
		else if (_pressed)
		{
			onClick(this, btn);
			if (_buttonType == ButtonType.SYNC)
			{
				_pressed = false;
				update_font_color();
			}
		}
	}

	/// Call this for ASYNC button to finish the click
	void signalClickEnd()
	{
		if (_buttonType == ButtonType.ASYNC && _pressed)
		{
			_pressed = false;
			update_font_color();
		}
	}

	Event!(void delegate(Button sender, sfMouseButton btn)) onClick;
}

Button asButton(GuiElement el)
{
	return cast(Button) el;
}
