module dsubs_common.containers.quadtree;

import std.algorithm: countUntil, remove, SwapStrategy;
import std.math;

public import gfm.math.vector;


// each cell node spans it's own square
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

	/// Get a square wich is this square's quarter inquadrant q
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

	/// Get a quadrant of point
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

	/// Get a square, for wich this square is a quarter. Center of the parent
	/// square is in quadrant q relative to this square's center.
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

	/// true when at least one of it's coordinates\dimensions is NaN
	bool anyNaN() const
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

	/// check this rectange against square on intersection\composition
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

private enum Quadrant: byte
{
	many = -1,
	lu = 0,		/// left up
	ld = 1,		/// left down
	rd = 2,		/// right down
	ru = 3		/// right up
}

private enum NodeType: byte
{
	cell,	/// cell node is a square wich holds leafs and may nest another 4 cells
	leaf	/// leaf node is the stored rectangle
}


/// Tree that holds rectangles and associated metadata of type T and supports
/// efficient spacial lookup.
final class QuadTree(T)
{
public:

	/// tree node that holds client's rectangle
	struct LeafNode
	{
		private Rectangle rect;
		T payload;
	}

	/// node of quadrtree, wich is a rectangle + metadata pair.
	struct Node
	{
		private NodeType type = NodeType.cell;
		private Node* parent = null;
		private NodeU data = { cell: CellNode.init };

		private alias data this;

		@property ref inout(T) payload() inout
		{
			assert(type == NodeType.leaf);
			return leaf.payload;
		}

		@property ref const(Rectangle) rect() const
		{
			return leaf.rect;
		}

		@property ref const(Rectangle) rect(Rectangle newRect)
		{
			assert(type == NodeType.leaf);
			assert(!newRect.anyNaN);
			// remove this node
			leaf.rect = newRect;
			// readd this node with a hint
			return leaf.rect;
		}
	}

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
		m_root = new Node();
		m_root.cell.area = Square(rootCenter, rootSquareSize);
	}

	/// create new leaf and return a handle to it
	Node* addLeaf(Rectangle rect, T payload)
	{
		assert(!rect.anyNaN());
		Node* holder = getToSmallestSpanning(m_root, rect);
		Node* leaf = new Node(NodeType.leaf, holder);
		leaf.leaf = LeafNode(rect, payload);
		holder.cell.leafChildren ~= leaf;
		incLeafCount(holder);
		return leaf;
	}

	/// remove node from the tree
	void removeLeaf(Node* leaf)
	{
		Node* p = leaf.parent;
		p.cell.leafChildren = remove!(SwapStrategy.unstable)(
			p.cell.leafChildren, countUntil(p.cell.leafChildren, leaf));
		leaf.parent = null;
		decLeafCount(p);
	}

	void findInCircle(vec2f center, float searchRadius, ref Node*[] result);

	void findInRectangle(ref const Rectangle searchArea, ref Node*[] result);

	void findUnderPoint(vec2f point, ref Node*[] result);

	void findCollisions(Node* suspect, ref Node*[] collidersFound);


private:

	struct CellNode
	{
		Square area;
		int leafCount = 0;		/// reference counter
		Node*[4] cellChildren;
		Node*[] leafChildren;
	}

	union NodeU
	{
		CellNode cell;
		LeafNode leaf;
	}

	Node* m_root;
	const float m_minSquareSize;

	/// get existing or create the smallest cell node that spans the rect
	Node* getToSmallestSpanning(Node* start, ref const Rectangle rect)
	{
		assert(start.type == NodeType.cell);
		Node* newPivot = walkUp(start, rect);
		// walkUp may walk well past root and create a new root
		if (m_root.parent !is null)
			m_root = newPivot;
		return walkDown(newPivot, rect);
	}

	/// get or create subsell, placed in quadrant q
	static Node* ensureQuadrantSubcell(Node* parent, Quadrant q)
	{
		assert(q >= 0);
		if (parent.cell.cellChildren[q] is null)
		{
			// create new subcell
			Node* newChild = new Node(NodeType.cell, parent);
			newChild.cell.area = parent.cell.area.getQuarter(q);
			parent.cell.cellChildren[q] = newChild;
			return newChild;
		}
		return parent.cell.cellChildren[q];
	}

	/// make sure child has a parent with center in quadrant q relative to child
	static Node* ensureParentSupercell(Node* child, Quadrant q)
	{
		assert(q >= 0);
		if (child.parent !is null)
			return child.parent;
		// new node must be created
		Node* parent = new Node(NodeType.cell);
		child.parent = parent;
		parent.cell.leafCount = child.cell.leafCount;
		parent.cell.cellChildren[(q + 2) % 4] = child;
		parent.cell.area = child.cell.area.getParent(q);
		return parent;
	}

	/// recursively descend down the cell (and create new cells if needed)
	/// chain and return the deepest cell wich spans rect
	Node* walkDown(Node* cur, ref const Rectangle rect)
	{
		Quadrant q = relateRectToCell(rect, cur.cell.area.center);
		if (q == Quadrant.many)
			return cur;
		if (cur.cell.area.side < 2.0f * m_minSquareSize)
			return cur;
		// we can subdivide
		Node* quadrantSubcell = ensureQuadrantSubcell(cur, q);
		return walkDown(quadrantSubcell, rect);
	}

	/// recursively ascend up (and create new cells if needed) and return the
	/// first cell wich spans rect completely
	static Node* walkUp(Node* cur, ref const Rectangle rect)
	{
		Relation rel = rect.relate(cur.cell.area);
		if (rel == Relation.inside)
			return cur;
		Quadrant q = cur.cell.area.getQuadrant(rect.center);
		Node* quadrantSupercell = ensureParentSupercell(cur, q);
		return walkUp(quadrantSupercell, rect);
	}

	/// return quadrant of rect relative to center
	static Quadrant relateRectToCell(ref const Rectangle rect, vec2f center)
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

	/// recursively increment leaf count for cell node
	static void incLeafCount(Node* node)
	{
		do
		{
			node.cell.leafCount++;
			node = node.parent;
		} while (node !is null);
	}

	/// recursively decrement leaf count for cell node, and destroy nodes
	/// that are no longer needed
	void decLeafCount(Node* node)
	{
		do
		{
			if (--node.cell.leafCount <= 0)
			{
				if (node is m_root)
					return;
				// leafCount is zero, this cell can be freed
				auto idx = countUntil(node.parent.cell.cellChildren[], node);
				node.parent.cell.cellChildren[idx] = null;
			}
			node = node.parent;
		} while (node !is null);
	}
}


unittest
{
	auto tree = new QuadTree!bool(1000.0f, 10.0f);
	auto node = tree.addLeaf(
		Rectangle(vec2f(514.0f, -133.0f), vec2f(23.0f, 2.0f)), false);
	assert(node.rect.center == vec2f(514.0f, -133.0f));
	assert(node.rect.size == vec2f(23.0f, 2.0f));
	assert(!node.payload);
	node = tree.addLeaf(
		Rectangle(vec2f(1514.0f, -2133.0f), vec2f(100.0f, 25.0f)), true);
	assert(tree.m_root.cell.leafCount == 2);
	assert(node.rect.center == vec2f(1514.0f, -2133.0f));
	assert(node.rect.size == vec2f(100.0f, 25.0f));
	assert(node.payload);
	tree.removeLeaf(node);
	assert(node.parent is null);
	assert(tree.m_root.cell.leafCount == 1);
}