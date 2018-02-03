module dsubs_common.containers.quadtree;

public import gfm.math.vector;


private struct Square
{
	vec2f center;
	float side;
}

struct Rectangle
{
	vec2f topLeft;
	vec2f size;
}

private enum NodeType: byte
{
	internal = 0,
	last = 1,
	leaf = 2
}


/// Tree that holds rectangles and supports efficient spacial lookup
struct QuadTree(T)
{

	private struct InternalNode
	{
		Square area;
		int leafCount = 0;
		Node*[4] internalChildren;

		alias lu = children[0];
		alias ru = children[1];
		alias ld = children[2];
		alias rd = children[3];

		Node*[] leafChildren;
	}

	private struct LastNode
	{
		Square area;
		Node*[] leafChildren;
	}

	private union NodeU
	{
		InternalNode inode;
		LastNode lastnode;
		TreeLeaf leafnode;
	}

	struct Node
	{
		private NodeType type = NodeType.internal;
		private Node* parent = null;
		private NodeU data;

		private ref InternalNode asInternal()
		{
			assert(type == NodeType.internal);
			return data.inode;
		}

		private ref LastNode asLast()
		{
			assert(type == NodeType.last);
			return data.lastnode;
		}

		ref TreeLeaf asLeaf()
		{
			assert(type == NodeType.leaf);
			return data.leafnode;
		}

		@property ref inout(T) payload() inout
		{
			assert(type == NodeType.leaf);
			return data.leafnode.payload;
		}

		@property Rectangle rect() const
		{
			return asLeaf.rect;
		}

		@property Rectangle rect(Rectangle newRect)
		{
			assert(type == NodeType.leaf);
			data.leafnode.rect = newRect;
			return data.leafnode.rect;
		}
	}

	struct TreeLeaf
	{
		private Rectangle rect;
		T payload;
	}

	private Node* root;
	private const float minSquareSize;

	@disable this();

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
		root.data.inode = InternalNode.init;
		root.data.inode.area.center = rootCenter;
		root.data.inode.area.side = rootSquareSize;
	}

	/// Create new leaf and return a handle to it
	Node* addLeaf(Rectangle rect, T payload);

	void removeLeaf(Node* leaf);

	void findInCircle(vec2f center, float searchRadius, ref Node*[] result);

	void findInRectangle(Rectangle searchArea, ref Node*[] result);

	void findUnderPoint(vec2f point, ref Node*[] result);

	void findCollisions(Node* suspect, ref Node*[] collidersFound);
}