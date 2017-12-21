module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

public import dsubs_client.core.utils;
import dsubs_client.core.event;
import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.input.router;


/// Layout policy used by layout managers.
enum LayoutType: byte
{
	FIXED,		/// element has fixed size
	CONTENT,	/// element size is dictated by it's content (textbox)
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

		/// cached viewport rectangle
		vec4i m_viewport;

		// if m_layoutType is FRACT, this is the fraction to use
		float m_fraction = 0.0f;
		LayoutType m_layoutType = LayoutType.GREEDY;
	}

	package GuiElement m_parent;	// layout manager of this element.

	this()
	{
		m_sfRst.blendMode = sfBlendAlpha;
		m_sfRect = sfRectangleShape_create();
		// Most elements don't have borders, and they don't manage them.
		sfRectangleShape_setOutlineThickness(rect, 0.0f);
		m_backgroudColor = sfTransparent;
	}

	/* The destructor for the super class automatically gets called when
	the destructor ends. There is no way to call the super destructor explicitly. */
	~this()
	{
		sfRectangleShape_destroy(rect);
	}

	final @property GuiElement parent() { return m_parent; }

	// Called by child when it's layout-related parameters have changed
	package void childChanged(GuiElement child) {}

	final @property vec2i position() const { return m_position; }

	@property vec2i position(in vec2i rhs)
	{
		m_position = rhs;
		updatePosition();
		return m_position;
	}

	final @property vec2i size() const { return m_size; }

	@property vec2i size(in vec2i rhs)
	{
		assert(rhs.x >= 0 && rhs.y >= 0);
		m_size = rhs;
		if ((m_layoutType == LayoutType.FIXED || m_layoutType == LayoutType.CONTENT) && m_parent)
			m_parent.childChanged(this);
		updateSize();
		return m_size;
	}

	final @property const(vec4i)* parentViewport() const { return m_parentViewport; }

	@property const(vec4i)* parentViewport(const(vec4i)* rhs)
	{
		m_parentViewport = rhs;
		updateViewport();
		return m_parentViewport;
	}

	final @property float fraction() const { return m_fraction; }

	@property float fraction(in float rhs)
	{
		assert(rhs >= 0.0f);
		m_fraction = rhs;
		if (m_layoutType == LayoutType.FRACT && m_parent)
			m_parent.childChanged(this);
		return m_fraction;
	}

	final @property LayoutType layoutType() const { return m_layoutType; }

	@property LayoutType layoutType(in LayoutType rhs)
	{
		m_layoutType = rhs;
		if (m_parent) 
			m_parent.childChanged(this);
		return m_layoutType;
	}

	/** Called by parent when it wants so set fixedDim axis size to fixedDimSize
	but wants the element to set the other dimention according to content size. 
	Returns content size. */
	package final int fitContent(Axis fixedDim, int fixedDimSize)
	{
		assert(m_layoutType == LayoutType.CONTENT);
		byte contentDim = fixDim ^ 1;	// xor 1 flips the bit
		m_size[fixedDim] = fixedDimSize;
		doFitContent(fixedDim);
		updateSize();
		return m_size[contentDim];
	}

	/// This function should actually implement scaling by content.
	protected void doFitContent(Axis fixedDim) {}

	//
	// rendering stuff
	//

	protected sfRenderStates m_sfRst;		// stores transform
	protected sfRectangleShape* m_sfRect;	// background rectangle
	
	private sfColor m_backgroundColor;

	final @property sfColor backgroundColor() const { return m_backgroundColor; }

	@property sfColor backgroundColor(in sfColor rhs)
	{
		m_backgroundColor = rhs;
		fRectangleShape_setFillColor(m_sfRect, m_backgroundColor);
		return m_backgroundColor;
	}

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

	private final void updateViewport()
	{
		if (m_parentViewport)
			m_viewport = clampViewport(m_parentViewport);
		else
			m_viewport = vec4i(m_position.x, m_position.y, m_size.x, m_size.y);
	}

	/// return intersection between rhs and this element's rectangle
	private final vec4i clampViewport(in vec4i* rhs) const
	{
		vec4i res;
		res[0] = min(max(rhs[0], m_position.x), m_position.x + m_size.x);
		res[1] = min(max(rhs[1], m_position.y), m_position.y + m_size.y);
		res[2] = min(rhs[2], max(0, m_position.x + m_size.x - res[0]));
		res[3] = min(rhs[3], max(0, m_position.y + m_size.y - res[1]));
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
		sfMouseButton btn, int delta)
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
		Router.kbFocused = this;
	}

	final void returnKbFocus()
	{
		if (m_kbFocused)
			Router.kbFocused = null;
	}

	final void requestMouseFocus()
	{
		Router.mouseFocused = this;
	}

	final void returnMouseFocus()
	{
		if (m_mouseFocused)
			Router.mouseFocused = null;
	}

	//
	// GUI-manager specifics
	//

	/// Return deepest GuiElement that contains the point, null otherwise.
	protected GuiElement getFromPoint(int x, int y)
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
		GuiElement interceptor = getFromPoint(x, y);
		if (interceptor)
			return GuiRouteResult(interceptor, interceptor.mouseTransparent);
		else
			return GuiRouteResult(null, true);
	}

	// events for users to subscribe to
	Event onMouseEnter;
	Event onMouseLeave;
	Event!(int x, int y) onMouseMove;
	Event!(int x, int y, sfMouseButton btn) onMouseDown;
	Event!(int x, int y, sfMouseButton btn) onMouseUp;
	Event!(int x, int y, int delta) onMouseScroll;
	Event!(const sfKeyEvent* evt) onKeyPressed;
	Event!(const sfKeyEvent* evt) onKeyReleased;
	Event!(const sfTextEvent* evt) onTextEntered;
}
