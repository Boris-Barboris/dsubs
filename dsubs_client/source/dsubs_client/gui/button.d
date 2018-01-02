module dsubs_client.gui.button;

import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_common.event;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.label;


enum ButtonType: ubyte
{
	SYNC,		/// onclick event is synchronous, instant return to unpressed state
	ASYNC,		/// onclick event is asynchronous, button must be unpressed from the outside
	TOGGLE		/// synchronous toggle
}

/// State wich is relevant for ASYNC and TOGGLE buttons.
enum ButtonState: bool
{
	INACTIVE = false,
	ACTIVE = true,		/// toggle is active, or asynchronous operation is running
}

class Button: Label
{
	private
	{
		ButtonType m_buttonType;
		sfColor m_textPressedColor = sfColor(255, 25, 25, 255);
		sfColor m_hoverColor = sfColor(255, 150, 150, 255);
		alias m_textReleasedColor = m_fontColor;

		/// true when user has pressed the button down, but didn't release it
		bool m_pressed;
		ButtonState m_state;	/// actual internal state of the button in toggle\async mode
	}

	this(ButtonType type = ButtonType.SYNC)
	{
		super();
		m_buttonType = type;
		updateFontColor();
		onMouseEnter += &handleMouseEnter;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseLeave += &handleMouseLeave;
	}

	final @property ButtonType buttonType() const { return m_buttonType; }

	mixin FinalGetSet!(sfColor, "textPressedColor", "updateFontColor();");
	mixin FinalGetSet!(sfColor, "textReleasedColor", "updateFontColor();");

	/// Intermidiate color between pressed and unpressed, used for hover
	mixin FinalGetSet!(sfColor, "hoverColor", "updateFontColor();");

	// whether user is currently holding the button down
	final @property bool pressed() const { return m_pressed; }

	private @property bool pressed(bool rhs)
	{
		m_pressed = rhs;
		updateFontColor();
		return m_pressed;
	}

	// internal state, bool. Is true when toggle is activated or
	// async button is in the process of click handling
	final @property ButtonState state() const { return m_state; }

	private void updateFontColor()
	{
		if (!m_pressed && m_underCursor)
		{
			sfText_setColor(m_sfText, m_hoverColor);
			return;
		}
		if (m_state != m_pressed)
			sfText_setColor(m_sfText, m_textPressedColor);
		else
			sfText_setColor(m_sfText, m_textReleasedColor);
	}

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		pressed = true;
	}

	private bool m_underCursor = false;

	private void handleMouseLeave()
	{
		m_underCursor = false;
		pressed = false;
	}

	private void handleMouseEnter()
	{
		m_underCursor = true;
		updateFontColor();
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (m_pressed)
		{
			simulateClick(btn);
			pressed = false;
		}
	}

	final void simulateClick(sfMouseButton btn = sfMouseLeft)
	{
		pressed = true;
		final switch (m_buttonType)
		{
			case ButtonType.TOGGLE:
				m_state = cast(ButtonState)!m_state;
				onClick(btn);
				break;
			case ButtonType.SYNC:
				onClick(btn);
				break;
			case ButtonType.ASYNC:
				if (m_state == ButtonState.INACTIVE)
				{
					m_state = ButtonState.ACTIVE;
					onClick(btn);
				}
		}
		pressed = false;
	}

	/// Call this for ASYNC button to finish the click
	void signalClickEnd()
	{
		assert(m_buttonType == ButtonType.ASYNC);
		m_state = ButtonState.INACTIVE;
		updateFontColor();
	}

	Event!(void delegate(sfMouseButton btn)) onClick;
}
