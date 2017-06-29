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
		bool _pressed, _state;
	}

	this(GuiManager manager)
	{
		super(manager);
		update_font_color();
		onMouseDown += &handle_mouse_down;
		onMouseUp += &handle_mouse_up;
		onMouseLeave += &handle_mouse_leave;
	}

	mixin ElementAccessor!(Button, ButtonType, "buttonType", "");
	mixin ElementAccessor!(Button, sfColor, "pressed_color", "update_font_color();");
	mixin ElementAccessor!(Button, sfColor, "released_color", "update_font_color();");

	mixin OverrideAccessor!(Button, sfColor, "font_color",
		"released_color(val);");

	bool pressed() { return _pressed; }

	protected void pressed(bool val)
	{
		_pressed = val;
		update_font_color();
	}

	// internal state, bool. Is true when toggle is activated or
	// async button is in the process of click handling
	bool state() { return _state; }

	protected void update_font_color()
	{
		bool visual_state = _state != _pressed;
		if (visual_state)
			sfText_setColor(text, _pressed_color);
		else
			sfText_setColor(text, _released_color);
	}

	protected void handle_mouse_down(GuiElement s, int x, int y, sfMouseButton btn)
	{
		pressed(true);
	}

	protected void handle_mouse_leave(GuiElement s)
	{
		pressed(false);
	}

	protected void handle_mouse_up(GuiElement s, int x, int y, sfMouseButton btn)
	{
		if (_pressed)
		{
			if (_buttonType == ButtonType.TOGGLE)
			{
				_state = !_state;
				onClick(this, btn);
			}
			else
			{
				if (_buttonType == ButtonType.ASYNC)
					_state = true;
				onClick(this, btn);
			}
			pressed(false);
		}
	}

	/// Call this for ASYNC button to finish the click
	void signalClickEnd()
	{
		assert(_buttonType == ButtonType.ASYNC);
		if (_state)
		{
			_state = false;
			update_font_color();
		}
	}

	Event!(void delegate(Button sender, sfMouseButton btn)) onClick;
}

Button asButton(GuiElement el)
{
	return cast(Button) el;
}
