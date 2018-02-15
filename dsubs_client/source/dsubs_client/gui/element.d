module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_common.event;

import dsubs_client.core.utils;
import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.gui.manager;
import dsubs_client.input.router;


/// Layout policy used by layout managers.
enum LayoutType: byte
{
	FIXED,		/// element has fixed size
	CONTENT,	/// element size is dictated by it's content (used in textbox)
	FRACT,		/// element takes fraction of space, left after FIXED elements
	GREEDY,		/// element tries to fill all available space in the container
}

enum Axis: byte
{
	X = 0,	/// horizontal
	Y = 1,	/// vertical
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: IInputReciever
{
	private
	{
		// layout parameters
		vec2i m_position;	// absolute position on the window
		vec2i m_size;		// absolute size

		/** parent viewport.
		If null, no intersection is performed.
		We use it separately instead of simply consulting parent
		element's viewport as a means of optimisation. Only
		scrollbar is actually setting it atm. */
		const(vec4i)* m_parentViewport = null;

		// if m_layoutType is FRACT, this is the fraction to use
		float m_fraction = 0.0f;
	}

	/// cached viewport rectangle
	protected vec4i m_viewport;
	protected LayoutType m_layoutType = LayoutType.GREEDY;

	package GuiElement m_parent;	// layout manager of this element.

	this()
	{
		m_sfRst.blendMode = sfBlendAlpha;
		m_sfRect = sfRectangleShape_create();
		// Most elements don't have borders, and they don't manage them.
		sfRectangleShape_setOutlineThickness(m_sfRect, 0.0f);
		m_backgroundColor = sfTransparent;
	}

	/* The destructor for the super class automatically gets called when
	the destructor ends. There is no way to call the super destructor explicitly. */
	~this()
	{
		sfRectangleShape_destroy(m_sfRect);
	}

	final @property GuiElement parent() { return m_parent; }

	// Called by child when it's layout-related parameters have changed
	void childChanged(GuiElement child) {}

	mixin GetSet!(vec2i, "position", "updatePosition();");

	final @property vec2i size() const { return m_size; }

	@property vec2i size(vec2i rhs)
	{
		assert(rhs.x >= 0 && rhs.y >= 0);
		m_size = rhs;
		if ((m_layoutType == LayoutType.FIXED || m_layoutType == LayoutType.CONTENT) &&
				m_parent)
			m_parent.childChanged(this);
		updateSize();
		return m_size;
	}

	/// same as size setter, but sets layout to fixed
	@property vec2i fixedSize(vec2i rhs)
	{
		m_layoutType = LayoutType.FIXED;
		size = rhs;
		return m_size;
	}

	mixin FinalGetSet!(const(vec4i)*, "parentViewport", "updateViewport();");

	/// when layoutType is FRACT, this is what is used to detrmine element size
	final @property float fraction() const { return m_fraction; }

	/// sets layoutType to fration
	final @property float fraction(float rhs)
	{
		assert(rhs >= 0.0f);
		m_fraction = rhs;
		layoutType = LayoutType.FRACT;
		return m_fraction;
	}

	final @property LayoutType layoutType() const { return m_layoutType; }

	@property LayoutType layoutType(LayoutType rhs)
	{
		m_layoutType = rhs;
		if (m_parent)
			m_parent.childChanged(this);
		return m_layoutType;
	}

	/** Called by parent when it wants so set fixedDim axis size to fixedDimSize
	but wants the element to set the other dimention according to it's content size.
	Returns content size. */
	package int fitContent(Axis fixedDim, int fixedDimSize)
	{
		assert(fixedDimSize >= 0);
		assert(m_layoutType == LayoutType.CONTENT);
		Axis contentDim = cast(Axis)(fixedDim ^ 1);	// xor 1 flips the bit
		m_size[fixedDim] = fixedDimSize;
		m_size[contentDim] = doFitContent(fixedDim, contentDim);
		updateSize();
		return m_size[contentDim];
	}

	/// This function should actually implement scaling by content.
	protected int doFitContent(Axis fixedDim, Axis contentDim)
	{
		return m_size[contentDim];
	}

	//
	// rendering stuff
	//

	protected sfRenderStates m_sfRst;		// stores transform
	protected sfRectangleShape* m_sfRect;	// background rectangle

	private sfColor m_backgroundColor;

	mixin FinalGetSet!(sfColor, "backgroundColor",
		"sfRectangleShape_setFillColor(m_sfRect, rhs);");

	/// set to true in order to render background
	bool backgroundVisible = false;

	protected void updatePosition()
	{
		updateViewport();
		m_sfRst.transform = sfTransform_Identity;
		sfTransform_translate(&m_sfRst.transform, m_position.x, m_position.y);
	}

	protected void updateSize()
	{
		updateViewport();
		sfRectangleShape_setSize(m_sfRect, m_size.tosf);
	}

	private void updateViewport()
	{
		if (m_parentViewport)
			m_viewport = clampViewport(m_parentViewport);
		else
			m_viewport = vec4i(m_position.x, m_position.y, m_size.x, m_size.y);
	}

	/// return intersection between rhs and this element's rectangle
	private vec4i clampViewport(const(vec4i)* rhs) const
	{
		vec4i res;
		res[0] = min(max((*rhs)[0], m_position.x), m_position.x + m_size.x);
		res[1] = min(max((*rhs)[1], m_position.y), m_position.y + m_size.y);
		int right = (*rhs)[0] + (*rhs)[2];
		int bottom = (*rhs)[1] + (*rhs)[3];
		res[2] = max(0, min(right, m_position.x + m_size.x - res[0]));
		res[3] = max(0, min(bottom, m_position.y + m_size.y - res[1]));
		return res;
	}

	void draw(Window wnd)
	{
		sfRenderWindow_setScissor(wnd.wnd, m_viewport.tosf);
		if (backgroundVisible)
			sfRenderWindow_drawRectangleShape(wnd.wnd, m_sfRect, &m_sfRst);
	}

	//
	// IInputReciever interface implementation
	//

	// Example implementation
	HandleResult handleKeyboard(Window wnd, const sfEvent* evt)
	{
		switch (evt.type)
		{
			case (sfEvtKeyPressed):
				onKeyPressed(cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtKeyReleased):
				onKeyReleased(cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtTextEntered):
				onTextEntered(cast(const sfTextEvent*) evt);
				break;
			default:
				assert(0, "can't handle non-keyboard event here");
		}
		return HandleResult(false);
	}

	void handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, float delta)
	{
		if (btn >= 0)
		{
			if (evt.type == sfEvtMouseButtonPressed)
				onMouseDown(x, y, btn);
			if (evt.type == sfEvtMouseButtonReleased)
				onMouseUp(x, y, btn);
		}
		else if (delta != 0)
			onMouseScroll(x, y, delta);
		else
			onMouseMove(x, y);
	}

	void handleMouseEnter()
	{
		onMouseEnter();
	}

	void handleMouseLeave()
	{
		onMouseLeave();
	}

	// focuses
	protected bool m_kbFocused = false;
	void handleKbFocusGain() { m_kbFocused = true; }
	void handleKbFocusLoss() { m_kbFocused = false; }
	protected bool m_mouseFocused = false;
	void handleMouseFocusGain() { m_mouseFocused = true; }
	void handleMouseFocusLoss() { m_mouseFocused = false; }

	// focus manipulation methods

	final void requestKbFocus()
	{
		InputRouter.kbFocused = this;
	}

	final void returnKbFocus()
	{
		if (m_kbFocused)
			InputRouter.kbFocused = null;
	}

	final void requestMouseFocus()
	{
		InputRouter.mouseFocused = this;
	}

	final void returnMouseFocus()
	{
		if (m_mouseFocused)
			InputRouter.mouseFocused = null;
	}

	//
	// GUI-manager specifics
	//

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if ((x >= m_position.x && x < m_position.x + m_size.x) &&
			(y >= m_position.y && y < m_position.y + m_size.y))
		{
			return this;
		}
		return null;
	}

	/// whether the element is transparent for mouse events
	bool mouseTransparent = true;

	// gui manager will query panels and seek first non-mouse-transparent
	// element wich is placed under cursor.
	package GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiElement interceptor = getFromPoint(evt, x, y);
		if (interceptor)
			return GuiRouteResult(interceptor, interceptor.mouseTransparent);
		else
			return GuiRouteResult(null, true);
	}

	// events for users to subscribe to
	Event!(void delegate()) onMouseEnter;
	Event!(void delegate()) onMouseLeave;
	Event!(void delegate(int x, int y)) onMouseMove;
	Event!(void delegate(int x, int y, sfMouseButton btn)) onMouseDown;
	Event!(void delegate(int x, int y, sfMouseButton btn)) onMouseUp;
	Event!(void delegate(int x, int y, float delta)) onMouseScroll;
	Event!(void delegate(const sfKeyEvent* evt)) onKeyPressed;
	Event!(void delegate(const sfKeyEvent* evt)) onKeyReleased;
	Event!(void delegate(const sfTextEvent* evt)) onTextEntered;
}


/// Create a transparent greedy-sized GuiElement
GuiElement filler()
{
	return new GuiElement();
}

/// Create a transparent GuiElement of fixed size
GuiElement filler(int size)
{
	GuiElement r = new GuiElement();
	r.fixedSize = vec2i(size, size);
	return r;
}

/// Create a transparent GuiElement of fractional size
GuiElement filler(float fract)
{
	GuiElement r = new GuiElement();
	r.fraction = fract;
	return r;
}