module dsubs_client.gui.div;

import std.algorithm;
import std.experimental.logger;
import std.conv: to;
import std.math;
import std.meta;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.gui.element;


enum DivType
{
	HORZ,	/// children are separated by vertical lines
	VERT	/// children are separated by horizontal lines
}

/// Linear layout manager, rectangular one-dimentional array of elements
final class Div: GuiElement
{
	public
	{
		immutable int dim;
		immutable int odim;
		immutable Axis fixedAxis;
	}

	private
	{
		private GuiElement[] m_children;
		bool m_updatingKids = false;	/// anti-recusrion flag.
		int m_borderWidth = 0;
		sfColor m_borderColor = sfTransparent;
		/// array of rectangles representing external border
		sfRectangleShape*[4] m_divBorders;
		/// array of rectangles that are used to draw inter-child borders
		sfRectangleShape*[] m_cellBorders;
	}

	this(DivType divType, GuiElement[] kids)
	{
		assert(kids.length > 0);
		
		if (divType == DivType.HORZ)
		{
			dim = 0;
			odim = 1;
			fixedAxis = Axis.Y;
		}
		else
		{
			dim = 1;
			odim = 0;
			fixedAxis = Axis.X;
		}

		super();
		m_children = kids;
		foreach (kid; m_children)
		{
			kid.m_parent = this;
			kid.parentViewport = &m_viewport;
		}
		// borders between m_children, kids.length - 1 borders to be exact
		foreach (ref brd; m_divBorders)
		{
			brd = sfRectangleShape_create();
			sfRectangleShape_setOutlineThickness(brd, 0);
			sfRectangleShape_setFillColor(brd, m_borderColor);
		}
		m_cellBorders.reserve(m_children.length - 1);
		for (int i = 1; i < m_children.length; i++)
		{
			sfRectangleShape* brd = sfRectangleShape_create();
			sfRectangleShape_setOutlineThickness(brd, 0);
			sfRectangleShape_setFillColor(brd, m_borderColor);
			m_cellBorders ~= brd;
		}
	}

	~this()
	{
		foreach (border; m_cellBorders)
			sfRectangleShape_destroy(border);
		foreach (border; m_divBorders)
			sfRectangleShape_destroy(border);
	}

	@property GuiElement[] children() { return m_children; }

	mixin FinalGetSet!(int, "borderWidth", "updateChildren();");

	mixin FinalGetSet!(sfColor, "borderColor", "updateBorderColor();");

	private void updateBorderColor()
	{
		foreach (r; m_cellBorders)
			sfRectangleShape_setFillColor(r, m_borderColor);
		foreach (r; m_divBorders)
			sfRectangleShape_setFillColor(r, m_borderColor);
	}

	override void childChanged(GuiElement child)
	{
		// kids are expected to notify us on their property changes
		if (!m_updatingKids)
			updateChildren();
	}

	private vec2i dimVec(int dimVal, int odimVal) const
	{
		vec2i res;
		res[dim] = dimVal;
		res[odim] = odimVal;
		return res;
	}

	private @property bool extBordersHidden() const
	{
		return (cast(Div) m_parent || (m_parent is null && layoutType == LayoutType.GREEDY));
	}

	// we don't display external border if our parent is div
	private @property int externalBorder() const
	{
		if (extBordersHidden)
			return 0;
		else
			return m_borderWidth;
	}

	private vec2i dimSizeVec(int dimVal) const
	{
		assert(dimVal >= 0);
		return dimVec(dimVal, max(0, size[odim] - 2 * externalBorder));
	}

	// recalculate children layout
	private void updateChildren()
	{
		m_updatingKids = true;
		int intBudget = size[dim] - m_borderWidth * (m_children.length - 1) - 
			2 * externalBorder;
		float budget = max(0, intBudget);
		// fixed-sized kids go first
		int childCount = 0;
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.FIXED))
		{
			float childSize = chip(budget, child.size[dim]);
			budget -= childSize;
			child.size = dimSizeVec(child.size[dim]);
			childCount++;
		}
		// content-sized kids determine their size on their own
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.CONTENT))
		{
			budget -= child.fitContent(fixedAxis, size[odim] - 2 * externalBorder);
			childCount++;
		}
		// now fractual kids
		auto fractKids = m_children.filter!(a => a.layoutType == LayoutType.FRACT);
		float fractSum = fold!((a, b) => a + b.fraction)(fractKids, 0.0f);
		fractSum = fmax(1.0f, fractSum);
		budget = fmax(0.0f, budget);
		float budgetSave = budget;
		foreach (child; fractKids)
		{
			float newSize = child.fraction / fractSum * budgetSave;
			child.size = dimSizeVec(lrint(newSize).to!int);
			budget -= newSize;
			childCount++;
		}
		// and now greedy ones
		int greedyCount = m_children.length - childCount;
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.GREEDY))
		{
			float newSize = chip(budget, budget / greedyCount);
			child.size = dimSizeVec(lrint(newSize).to!int);
		}
		// all offsets now are calcuated, we can set positions
		int offset = externalBorder;
		foreach (i, child; m_children)
		{
			child.position = position + dimVec(offset, externalBorder);
			offset += child.size[dim] + m_borderWidth;
		}
		m_updatingKids = false;
		updateBorderShapes();
	}

	private static float chip(float budget, float desiredVal)
	{
		return fmin(fmax(0.0f, budget), fmax(0.0f, desiredVal));
	}

	private void updateBorderShapes()
	{
		if (!extBordersHidden)
		{
			// update external borders:
			// top border
			sfRectangleShape_setPosition(m_divBorders[0], sfVector2f(0.0f, 0.0f));
			sfRectangleShape_setSize(m_divBorders[0],
				sfVector2f(size.x, m_borderWidth));
			// bottom border
			sfRectangleShape_setPosition(m_divBorders[2], sfVector2f(0.0f, size.y - m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[2], 
				sfVector2f(size.x, m_borderWidth));
			// left border
			sfRectangleShape_setPosition(m_divBorders[1], sfVector2f(0.0f, m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[1], 
				sfVector2f(m_borderWidth, size.y - 2 * m_borderWidth));
			// right border
			sfRectangleShape_setPosition(m_divBorders[3], sfVector2f(size.x - m_borderWidth, m_borderWidth));
			sfRectangleShape_setSize(m_divBorders[3], 
				sfVector2f(m_borderWidth, size.y - 2 * m_borderWidth));
		}
		// update inter-child borders
		auto newBorderSize = dimVec(m_borderWidth, m_children[0].size[odim]).tosf;
		int offset = externalBorder;
		foreach (i, sfBorderRect; m_cellBorders)
		{
			offset += m_children[i].size[dim];
			vec2i newBorderPos = dimVec(offset, externalBorder);
			sfRectangleShape_setPosition(sfBorderRect, newBorderPos.tosf);
			sfRectangleShape_setSize(sfBorderRect, newBorderSize);
			offset += m_borderWidth;
		}
	}

	alias position = super.position;

	override @property vec2i position(vec2i rhs)
	{
		vec2i diff = rhs - position;
		super.position = rhs;
		foreach (child; m_children)
			child.position = child.position + diff;
		return position;
	}

	override void updateSize()
	{
		super.updateSize();
		updateChildren();
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		if (!extBordersHidden)
			foreach (rect; m_divBorders)
				sfRenderWindow_drawRectangleShape(wnd.wnd, rect, &m_sfRst);
		foreach (rect; m_cellBorders)
			sfRenderWindow_drawRectangleShape(wnd.wnd, rect, &m_sfRst);
		foreach (child; m_children)
			child.draw(wnd);
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (super.getFromPoint(evt, x, y))
		{
			if (m_children.length == 0)
				return this;
			int offset = dim == 0 ? x - position.x : y - position.y;
			int cursor = externalBorder;
			foreach (kid; m_children)
			{
				auto check = kid.getFromPoint(evt, x, y);
				if (check)
					return check;
				cursor += kid.size[dim] + m_borderWidth;
				if (cursor >= offset)
					return this;
			}
			return this;
		}
		else
			return null;
	}
}

Div hDiv(GuiElement[] children) { return new Div(DivType.HORZ, children); }
Div vDiv(GuiElement[] children) { return new Div(DivType.VERT, children); }