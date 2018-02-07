module dsubs_common.containers.quadtree;

import std.algorithm: countUntil, remove, SwapStrategy;
import std.math;

public import gfm.math.vector;

import dsubs_common.containers.array;


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
		m_left = m_center.x - 0.5f * m_side;
		m_right = m_center.x + 0.5f * m_side;
		m_top = m_center.y + 0.5f * m_side;
		m_bottom = m_center.y - 0.5f * m_side;
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

	bool contains(vec2f point) const
	{
		if (point.x < left || point.x >= right || point.y < bottom || point.y >= top)
			return false;
		return true;
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
		m_left = m_center.x - 0.5f * m_size.x;
		m_right = m_center.x + 0.5f * m_size.x;
		m_top = m_center.y + 0.5f * m_size.y;
		m_bottom = m_center.y - 0.5f * m_size.y;
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

	bool contains(vec2f point) const
	{
		if (point.x < left || point.x >= right || point.y < bottom || point.y >= top)
			return false;
		return true;
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


/// Tree that holds rectangles and associated metadata of type T and supports
/// efficient spacial lookup.
final class QuadTree(T)
{
public:

	/// tree node that holds rectangle and user-defined payload
	struct LeafNode
	{
		private QuadTree!T m_tree;
		private CellNode* parent;
		private Rectangle m_rect;
		T payload;

		/// the tree this leaf belongs to
		@property QuadTree!T tree() { return m_tree; }

		/// rectangle, wich this leaf represents
		@property ref const(Rectangle) rect() const { return m_rect; }

		/// update the recnagle and reindex this leaf in the tree
		@property ref const(Rectangle) rect(Rectangle newRect)
		{
			assert(parent !is null && m_tree !is null, "Leaf is an orphan");
			assert(!newRect.anyNaN);
			m_rect = newRect;
			m_tree.reindexLeaf(&this);
			return m_rect;
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
		m_root = new CellNode();
		m_root.area = Square(rootCenter, rootSquareSize);
	}

	/// create new leaf and return a handle to it.
	LeafNode* addLeaf(Rectangle rect, T payload, LeafNode* hint = null)
	{
		assert(!rect.anyNaN);
		CellNode* start = m_root;
		if (hint !is null)
			start = hint.parent;
		CellNode* holder = getToSmallestSpanning(start, rect);
		LeafNode* leaf = new LeafNode(this, holder, rect, payload);
		holder.leafChildren ~= leaf;
		incLeafCount(holder);
		return leaf;
	}

	/// remove leaf from the tree
	void removeLeaf(LeafNode* leaf)
	{
		assert(leaf !is null);
		CellNode* p = leaf.parent;
		p.leafChildren.removeFirstUnstable(leaf);
		leaf.parent = null;
		decLeafCount(p);
	}

	/** append all leafs that have their center inside the circle to 'result'.
	if 'searchUp' is false, cells larger that the smallest cell spanning circle
	will not be checked */
	void findCentersInCircle(vec2f center, float searchRadius,
		ref LeafNode*[] result, bool searchUp = true) const
	{
		Rectangle searchRect = Rectangle(center, 2.0f * vec2f(searchRadius, searchRadius));
		const(CellNode)* start = walkDownConst(m_root, searchRect);
		float sqrSr = searchRadius * searchRadius;

		scope void delegate(const(CellNode*) cell) filterDlg = (cell) {
			foreach (const(LeafNode)* l; cell.leafChildren)
			{
				if ((l.rect.center - center).squaredLength <= sqrSr)
					result ~= cast(LeafNode*) l;
			}
		};

		// start itself and all of it's children are suspects
		applyRecursDownConst(start, filterDlg);
		// as well as all of it's parents
		if (searchUp && start.parent !is null)
			applyRecursUpConst(start.parent, filterDlg);
	}

	void findInRectangle(ref const Rectangle searchArea, ref LeafNode*[] result);

	/// append all leafs that contain 'point' in their rectangles to 'result'
	void findUnderPoint(vec2f point, ref LeafNode*[] result) const
	{
		const(CellNode)* node = m_root;
		while (node !is null && node.area.contains(point))
		{
			foreach (const(LeafNode)* l; node.leafChildren)
			{
				if (l.rect.contains(point))
					result ~= cast(LeafNode*) l;
			}
			Quadrant q = node.area.getQuadrant(point);
			node = node.cellChildren[q];
		}
	}

	void findCollisions(LeafNode* collider, ref LeafNode*[] result);


private:

	struct CellNode
	{
		CellNode* parent = null;
		Square area;
		int leafCount = 0;		/// reference counter
		CellNode*[4] cellChildren;
		LeafNode*[] leafChildren;
	}

	CellNode* m_root;
	const float m_minSquareSize;

	/// update leaf's position in the tree, because it's rectangle was updated
	void reindexLeaf(LeafNode* leaf)
	{
		CellNode* oldHolder = leaf.parent;
		CellNode* newHolder = getToSmallestSpanning(oldHolder, leaf.rect);
		if (newHolder !is oldHolder)
		{
			leaf.parent = newHolder;
			oldHolder.leafChildren.removeFirstUnstable(leaf);
			newHolder.leafChildren ~= leaf;
			incLeafCount(newHolder);
			decLeafCount(oldHolder);
		}
	}

	/// get existing or create the smallest cell node that spans the rect
	CellNode* getToSmallestSpanning(CellNode* start, ref const Rectangle rect)
	{
		CellNode* newPivot = walkUp(start, rect);
		// walkUp may walk well past root and create a new root
		if (m_root.parent !is null)
			m_root = newPivot;
		return walkDown(newPivot, rect);
	}

	/// get or create subsell, placed in quadrant q
	static CellNode* ensureQuadrantSubcell(CellNode* parent, Quadrant q)
	{
		assert(q >= 0);
		if (parent.cellChildren[q] is null)
		{
			// create new subcell
			CellNode* newChild = new CellNode(parent, parent.area.getQuarter(q));
			parent.cellChildren[q] = newChild;
			return newChild;
		}
		return parent.cellChildren[q];
	}

	/// make sure child has a parent with center in quadrant q relative to child
	static CellNode* ensureParentSupercell(CellNode* child, Quadrant q)
	{
		assert(q >= 0);
		if (child.parent !is null)
			return child.parent;
		// new node must be created
		CellNode* parent = new CellNode();
		child.parent = parent;
		parent.leafCount = child.leafCount;
		parent.cellChildren[(q + 2) % 4] = child;
		parent.area = child.area.getParent(q);
		return parent;
	}

	/// recursively descend down the cell (and create new cells if needed)
	/// tree and return the deepest cell wich spans rect
	CellNode* walkDown(CellNode* cur, ref const Rectangle rect)
	{
		Quadrant q = relateRectToCell(rect, cur.area.center);
		if (q == Quadrant.many)
			return cur;
		if (cur.area.side < 2.0f * m_minSquareSize)
			return cur;
		// we can subdivide
		CellNode* quadrantSubcell = ensureQuadrantSubcell(cur, q);
		return walkDown(quadrantSubcell, rect);
	}

	/// recursively descend down the cell tree
	/// and return the deepest cell wich spans rect
	static const(CellNode)* walkDownConst(const(CellNode)* cur, ref const Rectangle rect)
	{
		Quadrant q = relateRectToCell(rect, cur.area.center);
		if (q == Quadrant.many)
			return cur;
		if (cur.cellChildren[q] is null)
			return cur;
		return walkDownConst(cur.cellChildren[q], rect);
	}

	/// apply delegate to 'node' and all of it's subcells recursively
	static void applyRecursDownConst(
		const(CellNode)* node, scope void delegate(const(CellNode)*) dlg)
	{
		dlg(node);
		for (int i = 0; i < 4; i++)
		{
			if (node.cellChildren[i] !is null)
				applyRecursDownConst(node.cellChildren[i], dlg);
		}
	}

	/// apply delegate to 'node' and all of it's parents recursively
	static void applyRecursUpConst(
		const(CellNode)* node, scope void delegate(const(CellNode)*) dlg)
	{
		dlg(node);
		if (node.parent !is null)
			applyRecursUpConst(node.parent, dlg);
	}

	/// recursively ascend up (and create new cells if needed) and return the
	/// first cell wich spans rect completely
	static CellNode* walkUp(CellNode* cur, ref const Rectangle rect)
	{
		Relation rel = rect.relate(cur.area);
		if (rel == Relation.inside)
			return cur;
		Quadrant q = cur.area.getQuadrant(rect.center);
		CellNode* quadrantSupercell = ensureParentSupercell(cur, q);
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
	static void incLeafCount(CellNode* node)
	{
		do
		{
			node.leafCount++;
			node = node.parent;
		} while (node !is null);
	}

	/// recursively decrement leaf count for cell node, and destroy nodes
	/// that are no longer needed
	void decLeafCount(CellNode* node)
	{
		do
		{
			if (--node.leafCount <= 0)
			{
				if (node is m_root)
					return;
				// leafCount is zero, this cell can be freed
				auto idx = countUntil(node.parent.cellChildren[], node);
				node.parent.cellChildren[idx] = null;
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
	assert(tree.m_root.leafCount == 2);
	assert(node.rect.center == vec2f(1514.0f, -2133.0f));
	assert(node.rect.size == vec2f(100.0f, 25.0f));
	assert(node.payload);

	// reindex test
	node.rect = Rectangle(vec2f(514.0f, -133.0f), vec2f(23.0f, 2.0f));
	assert(node.rect.center == vec2f(514.0f, -133.0f));
	assert(node.rect.size == vec2f(23.0f, 2.0f));

	tree.removeLeaf(node);
	assert(node.parent is null);
	assert(tree.m_root.leafCount == 1);
}

unittest
{
	auto tree = new QuadTree!bool(1000.0f, 10.0f);
	auto node1 = tree.addLeaf(
		Rectangle(vec2f(0.0f, 0.0f), vec2f(20.0f, 20.0f)), false);
	auto node2 = tree.addLeaf(
		Rectangle(vec2f(0.0f, 0.0f), vec2f(500.0f, 500.0f)), false);
	auto node3 = tree.addLeaf(
		Rectangle(vec2f(-300.0f, 0.0f), vec2f(1000.0f, 1.0f)), false);
	typeof(node1)[] res;
	res.reserve(3);
	tree.findUnderPoint(vec2f(0.0f, 0.0f), res);
	assert(res.length == 3);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) >= 0);
	assert(res.countUntil(node3) >= 0);
	res.length = 0;
	tree.removeLeaf(node3);
	tree.findUnderPoint(vec2f(0.0f, 0.0f), res);
	assert(res.length == 2);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) >= 0);
	assert(res.countUntil(node3) < 0);
}

unittest
{
	auto tree = new QuadTree!bool(2.0f, 0.999f);
	auto node1 = tree.addLeaf(
		Rectangle(vec2f(0.5f, 0.5f), vec2f(0.4f, 0.4f)), false);
	typeof(node1)[] res;
	res.reserve(3);
	tree.findCentersInCircle(vec2f(0.0f, 0.0f), 0.5f, res);
	assert(res.length == 0);
	tree.findCentersInCircle(vec2f(0.0f, 0.0f), 1.0f, res);
	assert(res.length == 1);
	assert(res.countUntil(node1) >= 0);
	res.length = 0;
	tree.findCentersInCircle(vec2f(0.5f, 0.5f), 0.1f, res);
	assert(res.length == 1);
	assert(res.countUntil(node1) >= 0);
	res.length = 0;
	auto node2 = tree.addLeaf(
		Rectangle(vec2f(0.4f, 0.5f), vec2f(1.0f, 0.2f)), false);
	tree.findCentersInCircle(vec2f(0.0f, 0.0f), 1.0f, res);
	assert(res.length == 2);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) >= 0);
	res.length = 0;
	tree.findCentersInCircle(vec2f(0.5f, 0.5f), 0.2f, res, false);
	assert(res.length == 1);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) < 0);
	res.length = 0;
	auto node3 = tree.addLeaf(
		Rectangle(vec2f(-100.0f, 0.0f), vec2f(20.0f, 20.0f)), false);
	tree.findCentersInCircle(vec2f(0.0f, 0.0f), 1.0f, res);
	assert(res.length == 2);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) >= 0);
	assert(res.countUntil(node3) < 0);
	res.length = 0;
	tree.findCentersInCircle(vec2f(0.0f, 0.0f), 100.1f, res);
	assert(res.length == 3);
	assert(res.countUntil(node1) >= 0);
	assert(res.countUntil(node2) >= 0);
	assert(res.countUntil(node3) >= 0);
	res.length = 0;
}