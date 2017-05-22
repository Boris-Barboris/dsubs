module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_client.core.event;
import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
public import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.manager;


// Size types sorted in priority order. Same-type elements are treated
// equally
enum SizeType
{
	FIXED,	// element has fixed size
	FRACT,	// element takes fraction of free space, left after FIXED elements
	GREEDY	// element tries to fill all available space in the container.
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: Component!"Gui", IInputReciever
{
	package GuiElement _parent;
	protected
	{
		vec2f _position = vec2f(0, 0);
		vec2f _size = vec2f(0, 0);
		float _fraction = 0.0;
		SizeType _sizeType = SizeType.GREEDY;
	}

	this(GuiManager manager)
	{
		super(manager);
		rect = sfRectangleShape_create();
	}

	GuiManager manager() { return cast(GuiManager) _manager; }

	GuiElement parent() { return _parent; }

	// When we are disabled or enabled, we need to notify parent
	mixin SuperAccessor!(GuiElement, CompState, "state",
		"if (_parent) _parent.child_changed(this);");

	// Called by child when it has changed somehow
	void child_changed(GuiElement child) {}

	mixin ElementAccessor!(GuiElement, vec2f, "position",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec2f, "size",
		"if (_sizeType == SizeType.FIXED && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType", "");

	//
	// rendering stuff
	//

	protected
	{
		sfRectangleShape* rect;
	}

	bool _visible = true;

	protected
	{
		sfColor _backgroud_color = sfTransparent;
		sfColor _border_color = sfWhite;
		float _border_width = 1.0f;
		bool _visuals_dirty = true;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, sfColor, "border_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "border_width",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, bool, "visible", "");

	/// Update rendering-related parameters from state
	void update_visual()
	{
		sfRectangleShape_setPosition(rect, tosf(_position));
		sfVector2f new_size = tosf(_size);
		sfRectangleShape_setSize(rect, new_size);
		sfRectangleShape_setOutlineThickness(rect, _border_width);
		sfRectangleShape_setOutlineColor(rect, _border_color);
		sfRectangleShape_setFillColor(rect, _backgroud_color);
	}

	void draw(Window wnd)
	{
		if (visible)
		{
			if (_visuals_dirty)
				update_visual();
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
		}
	}

	//
	// Event handling
	//

	//
	// IInputReciever interface
	//

	void handleMouseEnter()
	{
		onMouseEnter(this);
	}

	void handleMouseLeave()
	{
		onMouseLeave(this);
	}

	// called when keyboard is being exclusively captured.
	// Example implementation.
	HandleResult handleKeyboard(const sfEvent* evt)
	{
		if (!this.active)
			return HandleResult(true, true);
		switch (evt.type)
		{
			case (sfEvtKeyPressed):
				onKeyPressed(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtKeyReleased):
				onKeyReleased(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtTextEntered):
				onTextEntered(this, cast(const sfTextEvent*) evt);
				break;
			default:
				return HandleResult(true, true);
		}
		// just give the focus away and pass through
		return HandleResult(true, true);
	}

	// called when exclusive mouse focus is being captured
	HandleResult handleMouse(const sfEvent* evt)
	{
		// mock
		if (!this.active)
			return HandleResult(true, true);
		return HandleResult(false, false);
	}

	// focuses
	protected bool kb_focused = false;
	void handleKbFocusGain() { kb_focused = true; }
	void handleKbFocusLoss() { kb_focused = false; }
	protected bool mouse_focused = false;
	void handleMouseFocusGain() { mouse_focused = true; }
	void handleMouseFocusLoss() { mouse_focused = false; }

	// focus manipulation methods

	void requestKbFocus()
	{
		manager.router.kbFocus(this);
	}

	void returnKbFocus()
	{
		if (kb_focused)
			manager.router.kbFocus(null);
	}

	void requestMouseFocus()
	{
		manager.router.mouseFocus(this);
	}

	void returnMouseFocus()
	{
		if (mouse_focused)
			manager.router.mouseFocus(null);
	}

	//
	// GUI-manager specifics
	//

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement get_from_point(vec2f point)
	{
		if (!this.active)
			return null;
		if ((point.x >= position.x && point.x < position.x + size.x) &&
			(point.y >= position.y && point.y < position.y + size.y))
			return this;
		else
			return null;
	}

	package GuiHandleResult handleMousePosEvent(const sfEvent* evt,
		int x, int y, sfMouseButton btn, int delta)
	{
		GuiElement interceptor = get_from_point(vec2f(x, y));
		if (interceptor == this)
		{
			if (btn >= 0)
			{
				if (evt.type == sfEvtMouseButtonPressed)
					onMouseDown(this, x, y, btn);
				if (evt.type == sfEvtMouseButtonReleased)
					onMouseUp(this, x, y, btn);
			}
			else if (delta != 0)
				onMouseScroll(this, x, y, delta);
			else
				onMouseMove(this, x, y);
			return GuiHandleResult(HandleResult(false, true), this);
		}
		else if (interceptor)
			return interceptor.handleMousePosEvent(evt, x, y, btn, delta);
		return GuiHandleResult(HandleResult(true, true), null);
	}


	// events for users to subscribe to
	Event!(void delegate(GuiElement sender)) onMouseEnter;
	Event!(void delegate(GuiElement sender)) onMouseLeave;
	Event!(void delegate(GuiElement sender, int x, int y)) onMouseMove;
	Event!(void delegate(GuiElement sender, int x, int y, sfMouseButton btn)) onMouseDown;
	Event!(void delegate(GuiElement sender, int x, int y, sfMouseButton btn)) onMouseUp;
	Event!(void delegate(GuiElement sender, int x, int y, int delta)) onMouseScroll;
	Event!(void delegate(GuiElement sender, const sfKeyEvent* evt)) onKeyPressed;
	Event!(void delegate(GuiElement sender, const sfKeyEvent* evt)) onKeyReleased;
	Event!(void delegate(GuiElement sender, const sfTextEvent* evt)) onTextEntered;
}

template isGuiElement(T)
{
	enum isGuiElement = is(T: GuiElement);
}
