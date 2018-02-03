module dsubs_common.containers.quadtree;

import std.math;

public import gfm.math.vector;


// each cell node spans a square
private struct Square
{
	vec2f center;
	float side;

	@property float left() const { return center.x - side / 2.0f; }
	@property float right() const { return center.x + side / 2.0f; }
	@property float top() const { return center.y + side / 2.0f; }
	@property float bottom() const { return center.y - side / 2.0f; }
}

struct Rectangle
{
	vec2f center;
	vec2f size;

	@property bool isNaN() const
	{
		return isNaN(center.x) || isNaN(center.y) || isNaN(size.x) || isNaN(size.y);
	}

	@property float left() const { return center.x - size.x / 2.0f; }
	@property float right() const { return center.x + size.x / 2.0f; }
	@property float top() const { return center.y + size.y / 2.0f; }
	@property float bottom() const { return center.y - size.y / 2.0f; }

	private Relation relate(Square sqr) const
	{
		if (right < sqr.left || left > sqr.right)
			return Relation.outside;
		if (bottom > sqr.top || top < sqr.bottom)
			return Relation.outside;
		if (left >= sqr.left && right <= sqr.right &&
			top <= sqr.top && bottom >= sqr.bottom)
			return Relation.inside;
		return Relation.intersect;
	}
}

private enum Relation
{
	inside,
	intersect,
	outside
}

private enum NodeType: byte
{
	cell = 0,	// cell node is a square wich holds leafs and may nest another 4 nested cells
	leaf = 1	// leaf node is an actual rectangle
}


/// Tree that holds rectangles an their associated metadata and supports
/// efficient spacial lookup
final class QuadTree(T)
{

	private struct CellNode
	{
		Square area;
		int leafCount = 0;
		Node*[4] cellChildren;

		alias lu = cellChildren[0];
		alias ru = cellChildren[1];
		alias ld = cellChildren[2];
		alias rd = cellChildren[3];

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

		@property Rectangle rect() const
		{
			return asLeaf.rect;
		}

		@property Rectangle rect(Rectangle newRect)
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
	the minimal square size of internal node - the last node beyond the leaf.
	*/
	this(float rootSquareSize, float minSquareSize,
		vec2f rootCenter = vec2f(0.0f, 0.0f))
	{
		assert(minSquareSize <= rootSquareSize);
		this.minSquareSize = minSquareSize;
		root = new Node();
		root.data.cell = CellNode.init;
		root.data.cell.area = Square(rootCenter, rootSquareSize);
	}

	/// Create new leaf and return a handle to it
	Node* addLeaf(Rectangle rect, T payload)
	{
		assert(!rect.isNaN);
	}

	// get existing or create the smallest cell node that spans the rect
	private Node* getToSmallestSpanning(Node* start, const ref Rectangle rect)
	{
		if (rect.relate(start.asCell.area) == Relation.inside)
		{
			// rectangle is inside 
		}
	}

	// 0 - lu, 1 - ru, 2 - ld, 3 - rd
	private static int getQuadrant(const ref Rectangle rect, Square sqr)
	{
		if (rect.right < sqr.center.x)	// left half-plane
		{
			if (rect.top < sqr.center.y)	// bottom half-plane
				return 2;
			else if (rect.bottom >= sqr.center.y)	// top hald-plane
				return 0;
		}
		else if (rect.left >= sqr.center.x)	// right half-plane
		{
			if (rect.top < sqr.center.y)	// bottom half-plane
				return 3;
			else if (rect.bottom >= sqr.center.y)	// top hald-plane
				return 1;
		}
		return -1;
	}

	private static Node* goDown(Node* cur, const ref Rectangle rect)
	{

	}

	void removeLeaf(Node* leaf);

	void findInCircle(vec2f center, float searchRadius, ref Node*[] result);

	void findInRectangle(Rectangle searchArea, ref Node*[] result);

	void findUnderPoint(vec2f point, ref Node*[] result);

	void findCollisions(Node* suspect, ref Node*[] collidersFound);
}