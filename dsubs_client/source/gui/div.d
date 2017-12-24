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
final class Div(DivType divType): GuiElement
{
	private
	{
		private GuiElement[] m_children;
		bool m_updatingKids = false;	/// anti-recusrion flag.
		int m_borderWidth = 1;
		sfColor m_borderColor = sfColor(150, 150, 150, 150);
		/// array of rectangles that are used to draw inter-child borders
		sfRectangleShape*[] m_cellBorders;
	}

	this(GuiElement[] kids)
	{
		assert(kids.length > 0);
		super();
		m_children = kids;
		foreach (kid; m_children)
		{
			kid.m_parent = this;
			kid.parentViewport = &m_viewport;
		}
		// borders between m_children, kids.length - 1 borders to be exact
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
	}

	private
	{
		static if (divType == DivType.HORZ)
		{
			enum dim = 0;
			enum odim = 1;
			enum Axis fixedAxis = Axis.Y;
		}
		else
		{
			enum dim = 1;
			enum odim = 0;
			enum Axis fixedAxis = Axis.X;
		}
	}

	@property GuiElement[] children() { return m_children; }

	mixin FinalGetSet!(int, "borderWidth", "updateBorderWidth();");

	mixin FinalGetSet!(sfColor, "borderColor", "updateBorderColor();");

	private void updateBorderWidth()
	{
		sfRectangleShape_setOutlineThickness(m_sfRect, m_borderWidth);
		updateChildren();
	}

	private void updateBorderColor()
	{
		sfRectangleShape_setOutlineColor(m_sfRect, m_borderColor);
		foreach (r; m_cellBorders)
			sfRectangleShape_setFillColor(r, m_borderColor);
	}

	override void childChanged(GuiElement child)
	{
		// kids are expected to notify us on their property changes
		if (!m_updatingKids)
			updateChildren();
	}

	private static vec2i dimVec(int dimVal, int odimVal)
	{
		vec2i res;
		res[dim] = dimVal;
		res[odim] = odimVal;
		return res;
	}

	private vec2i dimSizeVec(int dimVal) const
	{
		assert(dimVal >= 0);
		return dimVec(dimVal, max(0, size[odim] - 2 * m_borderWidth));
	}

	// recalculate children layout
	private void updateChildren()
	{
		m_updatingKids = true;
		int intBudget = size[dim] - m_borderWidth * (1 + m_children.length);
		float budget = max(0, intBudget);
		// fixed-sized kids go first
		int childCount = 0;
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.FIXED))
		{
			float childSize = chip(budget, child.size[dim]);
			budget -= childSize;
			child.size(dimSizeVec(child.size[dim]));
			childCount++;
		}
		// content-sized kids determine their size on their own
		foreach (child; m_children.filter!(a => a.layoutType == LayoutType.CONTENT))
		{
			budget -= child.fitContent(fixedAxis, size[odim]);
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
		int offset = m_borderWidth;
		foreach (i, child; m_children)
		{
			child.position = position + dimVec(offset, m_borderWidth);
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
		auto newBorderSize = dimVec(m_borderWidth, m_children[0].size[odim]).tosf;
		int offset = 0;
		foreach (i, sfBorderRect; m_cellBorders)
		{
			offset += m_children[i].size[dim] + m_borderWidth;
			vec2i newBorderPos = dimVec(offset, m_borderWidth);
			sfRectangleShape_setPosition(sfBorderRect, newBorderPos.tosf);
			sfRectangleShape_setSize(sfBorderRect, newBorderSize);
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
		foreach (sfBorderRect; m_cellBorders)
			sfRenderWindow_drawRectangleShape(wnd.wnd, sfBorderRect, &m_sfRst);
		foreach (child; m_children)
			child.draw(wnd);
	}

	override GuiElement getFromPoint(int x, int y)
	{
		if (super.getFromPoint(x, y))
		{
			if (m_children.length == 0)
				return this;
			static if (divType == DivType.HORZ)
				int offset = x - position.x;
			else
				int offset = y - position.y;
			int cursor = m_borderWidth;
			foreach (kid; m_children)
			{
				auto check = kid.getFromPoint(x, y);
				if (check)
					return check;
				cursor += kid.size[dim] + m_borderWidth;
				if (cursor >= offset)
					return this;
			}
			assert(0, "impossible");
		}
		else
			return null;
	}
}

alias HDiv = Div!(DivType.HORZ);
alias VDiv = Div!(DivType.VERT);
