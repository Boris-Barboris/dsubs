module dsubs_client.gui.button;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.event;
import dsubs_client.core.window;
import dsubs_client.gui.label;


enum ButtonType: ubyte
{
	SYNC,		// onclick event is synchronous, instant return to unpressed state
	ASYNC,		// onclick event is asynchronous, unpressed after
				// callback was called from the outside
	TOGGLE		// synchronous toggle
}

final class Button: Label
{
	private
	{
		ButtonType _buttonType;
		sfColor _pressed_color = sfRed;
		sfColor _released_color = sfWhite;
		bool _pressed;    // true when user pressed mouse down but didn't release it
        bool _state;      // actual internal state of the button in toggle\async mode
	}

	this()
	{
		super();
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

	// whether user is currently holding the button down
	@propery bool pressed() const { return _pressed; }

	private void pressed(bool val)
	{
		_pressed = val;
		update_font_color();
	}

	// internal state, bool. Is true when toggle is activated or
	// async button is in the process of click handling
	@property bool state() const { return _state; }

	private void update_font_color()
	{
		bool visual_state = (_state != _pressed);
		if (visual_state)
			sfText_setColor(text, _pressed_color);
		else
			sfText_setColor(text, _released_color);
	}

	private void handle_mouse_down(GuiElement s, int x, int y, sfMouseButton btn)
	{
		pressed(true);
	}

	private void handle_mouse_leave(GuiElement s)
	{
		pressed(false);
	}

	private void handle_mouse_up(GuiElement s, int x, int y, sfMouseButton btn)
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

	Event!(Button sender, sfMouseButton btn) onClick;
}

Button asButton(GuiElement el)
{
	return cast(Button) el;
}
