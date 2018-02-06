module dsubs_common.containers.quadtree;

import std.math;

public import gfm.math.vector;


// each cell node spans a square
private struct Square
{
	private
	{
		vec2f m_center;
		float m_side;

		float m_left;
		float m_right;
		float m_top;
		float m_bottom;
	}

	this(vec2f center, float side)
	{
		m_center = center;
		m_side = side;
		updateLrtb();
	}

	@property vec2f center() const { return m_center; }
	@property vec2f center(vec2f rhs)
	{
		m_center = rhs;
		updateLrtb();
		return m_center;
	}

	@property float side() const { return m_side; }
	@property float side(float rhs)
	{
		m_side = rhs;
		updateLrtb();
		return m_side;
	}

	private void updateLrtb()
	{
		m_left = m_center.x - m_side;
		m_right = m_center.x + m_side;
		m_top = m_center.y + m_side;
		m_bottom = m_center.y - m_side;
	}

	@property float left() const { return m_left; }
	@property float right() const { return m_right; }
	@property float top() const { return m_top; }
	@property float bottom() const { return m_bottom; }

	Square getQuarter(Quadrant q) const
	{
		final switch (q)
		{
			case Quadrant.lu: return Square(m_center +
				0.25f * vec2f(-m_side, m_side), 0.5f * m_side);
			case Quadrant.ld: return Square(m_center +
				0.25f * vec2f(-m_side, -m_side), 0.5f * m_side);
			case Quadrant.rd: return Square(m_center +
				0.25f * vec2f(m_side, -m_side), 0.5f * m_side);
			case Quadrant.ru: return Square(m_center +
				0.25f * vec2f(m_side, m_side), 0.5f * m_side);
			case Quadrant.many:
				assert(0, "invalid quadrant input");
		}
	}

	Quadrant getQuadrant(vec2f point) const
	{
		if (point.x < m_center.x)
		{
			if (point.y >= m_center.y)
				return Quadrant.lu;
			return Quadrant.ld;
		}
		if (point.y >= m_center.y)
			return Quadrant.ru;
		return Quadrant.rd;
	}

	Square getParent(Quadrant q) const
	{
		final switch (q)
		{
			case Quadrant.lu: return Square(m_center +
				0.5f * vec2f(-m_side, m_side), 2.0f * m_side);
			case Quadrant.ld: return Square(m_center +
				0.5f * vec2f(-m_side, -m_side), 2.0f * m_side);
			case Quadrant.rd: return Square(m_center +
				0.5f * vec2f(m_side, -m_side), 2.0f * m_side);
			case Quadrant.ru: return Square(m_center +
				0.5f * vec2f(m_side, m_side), 2.0f * m_side);
			case Quadrant.many:
				assert(0, "invalid quadrant input");
		}
	}
}


struct Rectangle
{
	private
	{
		vec2f m_center;
		vec2f m_size;

		float m_left;
		float m_right;
		float m_top;
		float m_bottom;
	}

	@property bool isNaN() const
	{
		return isNaN(center.x) || isNaN(center.y) || isNaN(size.x) || isNaN(size.y);
	}

	this(vec2f center, vec2f size)
	{
		m_center = center;
		m_size = size;
		updateLrtb();
	}

	@property vec2f center() const { return m_center; }
	@property vec2f center(vec2f rhs)
	{
		m_center = rhs;
		updateLrtb();
		return m_center;
	}

	@property vec2f size() const { return m_size; }
	@property vec2f size(vec2f rhs)
	{
		m_size = rhs;
		updateLrtb();
		return m_size;
	}

	private void updateLrtb()
	{
		m_left = m_center.x - m_size.x;
		m_right = m_center.x + m_size.x;
		m_top = m_center.y + m_size.y;
		m_bottom = m_center.y - m_size.y;
	}

	@property float left() const { return m_left; }
	@property float right() const { return m_right; }
	@property float top() const { return m_top; }
	@property float bottom() const { return m_bottom; }

	private Relation relate(ref const Square sqr) const
	{
		if (right < sqr.left || left >= sqr.right)
			return Relation.outside;
		if (bottom >= sqr.top || top < sqr.bottom)
			return Relation.outside;
		if (left >= sqr.left && right < sqr.right &&
			top < sqr.top && bottom >= sqr.bottom)
			return Relation.inside;
		return Relation.intersect;
	}
}

private enum Relation: byte
{
	inside,
	intersect,
	outside
}

enum Quadrant: byte
{
	many = -1,
	lu = 0,		/// left up
	ld = 1,		/// left down
	rd = 2,		/// right down
	ru = 3		/// right up
}

private enum NodeType: byte
{
	cell,	// cell node is a square wich holds leafs and may nest another 4 cells
	leaf	// leaf node is an actual rectangle
}


/// Tree that holds rectangles an their associated metadata and supports
/// efficient spacial lookup
final class QuadTree(T)
{
	private struct CellNode
	{
		Square area;
		int leafCount = 0;		/// reference counter
		Node*[4] cellChildren;

		alias lu = cellChildren[0];
		alias ld = cellChildren[1];
		alias rd = cellChildren[2];
		alias ru = cellChildren[3];

		Node*[] leafChildren;
	}

	/// tree node that holds client's rectangle
	struct LeafNode
	{
		private Rectangle rect;
		T payload;
	}

	private union NodeU
	{
		CellNode cell;
		LeafNode leaf;
	}

	struct Node
	{
		private NodeType type = NodeType.internal;
		private Node* parent = null;
		private NodeU data;

		private ref inout(CellNode) asCell() inout
		{
			assert(type == NodeType.cell);
			return data.cell;
		}

		private alias cell = data.cell;

		ref inout(LeafNode) asLeaf() inout
		{
			assert(type == NodeType.leaf);
			return data.leaf;
		}

		@property ref inout(T) payload() inout
		{
			assert(type == NodeType.leaf);
			return data.leaf.payload;
		}

		@property ref const Rectangle rect() const
		{
			return asLeaf.rect;
		}

		@property ref const Rectangle rect(Rectangle newRect)
		{
			assert(type == NodeType.leaf);
			assert(!newRect.isNaN);
			data.leaf.rect = newRect;
			return data.leaf.rect;
		}
	}

	private Node* m_root;
	private const float m_minSquareSize;

	/**
	Initializes quadrtree with root internal node spanning the square, centered
	at 'rootCenter' with edge of 'rootSquareSize'. 'minSquareSize' will be
	the minimal square size of internal node.
	*/
	this(float rootSquareSize, float minSquareSize,
		vec2f rootCenter = vec2f(0.0f, 0.0f))
	{
		assert(minSquareSize <= rootSquareSize);
		this.m_minSquareSize = minSquareSize;
		root = new Node(Square(rootCenter, rootSquareSize), null, CellNode.init);
	}

	/// Create new leaf and return a handle to it
	Node* addLeaf(Rectangle rect, T payload)
	{
		assert(!rect.isNaN);
	}

	// get existing or create the smallest cell node that spans the rect
	private static Node* getToSmallestSpanning(Node* start, ref const Rectangle rect)
	{
		Relation rel = rect.relate(start.asCell.area);
		final switch (rel)
		{
			case Relation.inside:
				// rectangle is inside
				return walkDown(start, rect);
			case Relation.outside:
			case Relation.intersect:
				Node* newPivot = walkUp(start, rect);
				// walkUp may walk well past root and create the new root
				// effectively
				if (m_root.parent !is null)
					m_root = newPivot;
				return walkDown(newPivot, rect);
		}
	}

	/// get or create cubsell, placed in quadrant q
	private static Node* ensureQuadrantSubcell(Node* parent, Quadrant q)
	{
		assert(q >= 0);
		assert(parent !is null);
		if (parent.cell.cellChildren[q] is null)
		{
			// create new subcell
			Node* newChild = new Node(NodeType.cell, parent, CellNode.init);
			newChild.cell.area = parent.cell.area.getQuarter(q);
			parent.cell.cellChildren[q] = newChild;
			return newChild;
		}
		return parent.cell.cellChildren[q];
	}

	// make sure child has a parent with center in quadrant q relative to child
	private static Node* ensureParentSupercell(Node* child, Quadrant q)
	{
		assert(child !is null);
		if (child.parent !is null)
			return child.parent;
		Node* parent = new Node(NodeType.cell, parent, CellNode.init);
		child.parent = parent;
		parent.cell.cellChildren[q + 2 % 4] = child;
		// new parent inherits his child's leafCount
		parent.cell.leafCount = child.cell.leafCount;
		return parent;
	}

	// recursively descend down the cell (and create new cells if needed)
	// chain and return the deepest cell wich spans rect
	private static Node* walkDown(Node* cur, ref const Rectangle rect)
	{
		assert(cur !is null);
		assert(cur.type == NodeType.cell);
		Quadrant q = relateRectToCell(rect, cur.cell.area.center);
		if (q == Quadrant.many)
			return cur;
		if (cur.cell.area.side < 2.0f * m_minSquareSize)
			return cur;
		// we can subdivide
		Node* quadrantSubcell = ensureQuadrantSubcell(cur, q);
		return walkDown(quadrantSubcell, rect);
	}

	private static Node* walkUp(Node* cur, ref const Rectangle rect)
	{
		assert(cur !is null);
		assert(cur.type == NodeType.cell);
		Relation rel = rect.relate(cur.cell.area);
		if (rel == Relation.inside)
			return cur;
		Quadrant q = cur.cell.area.getQuadrant(rect.center);

	}

	private static Quadrant relateRectToCell(ref const Rectangle rect, vec2f center)
	{
		if (rect.right < center.x)	// left half-plane
		{
			if (rect.top < center.y)	// bottom half-plane
				return Quadrant.ld;
			else if (rect.bottom >= center.y)	// top half-plane
				return Quadrant.lu;
		}
		else if (rect.left >= center.x)	// right half-plane
		{
			if (rect.top < center.y)	// bottom half-plane
				return Quadrant.rd;
			else if (rect.bottom >= center.y)	// top half-plane
				return Quadrant.ru;
		}
		return Quadrant.many;
	}

	void removeLeaf(Node* leaf);

	void findInCircle(vec2f center, float searchRadius, ref Node*[] result);

	void findInRectangle(ref const Rectangle searchArea, ref Node*[] result);

	void findUnderPoint(vec2f point, ref Node*[] result);

	void findCollisions(Node* suspect, ref Node*[] collidersFound);
}