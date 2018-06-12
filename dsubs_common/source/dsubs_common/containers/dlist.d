module dsubs_common.containers.dlist;

import std.functional: unaryFun;


/// Double-linked list that is more transparent than phobos variant.
struct DList(T)
{
	static struct DNode
	{
		DNode* prev;
		DNode* next;
		T val;

		@disable this();

		this(DNode* p, DNode* n, ref T v)
		{
			prev = p;
			next = n;
			val = v;
			if (p)
				p.next = &this;
			if (n)
				n.prev = &this;
		}
	}

	DNode* _first, _last;

	ref T front()
	{
		assert(!empty, "list is empty");
		return _first.val;
	}

	ref T back()
	{
		assert(!empty, "list is empty");
		return _last.val;
	}

	@disable this(this);

	this(T[] range)
	{
		foreach (el; range)
			this.insertBack(el);
	}

	void clear()
	{
		_first = _last = null;
		assert(empty);
	}

	// Bidirectional iterator that wraps raw node interactions
	struct Iterator
	{
		DNode* _target;
		this(DNode* tgt) { _target = tgt; }
		@property ref T val()
		{
			assert(!this.end);
			return _target.val;
		}
		void next()
		{
			assert(!this.end);
			_target = _target.next;
		}
		void prev()
		{
			assert(!this.end);
			_target = _target.prev;
		}
		@property bool end() const { return _target is null; }
	}

	struct Range
	{
		Iterator first, last;
		this(Iterator first, Iterator last)
		{
			this.first = first;
			this.last = last;
		}
		@property ref T front()
		{
			assert(!empty);
			return first.val;
		}
		@property ref T back()
		{
			assert(!empty);
			return last.val;
		}
		void popFront()
		{
			assert(!empty);
			first.next();
		}
		void popBack()
		{
			assert(!empty);
			last.prev();
		}
		@property bool empty() const
		{
			if (first.end || last.end)
				return true;
			return first._target.prev is last._target;
		}
		@property Range save() { return this; }
	}

	Range opSlice()
	{
		return Range(first, last);
	}

	/// Get iterator that points to first node.
	@property Iterator first() { return Iterator(_first); }

	/// Get iterator that points to last node.
	@property Iterator last() { return Iterator(_last); }

	/// Remove node under cursor. Cursor keeps pointing to the deleted node.
	void remove(Iterator cursor)
	{
		assert(!cursor.end);
		DNode* node = cursor._target;
		if (_first is node)
			_first = node.next;
		if (_last is node)
			_last = node.prev;
		if (node.prev)
			node.prev.next = node.next;
		if (node.next)
			node.next.prev = node.prev;
	}

	@property bool empty() const
	{
		return _first == null;
	}

	DNode* create_node(DNode* prev, DNode* next, ref T val)
	{
		return new DNode(prev, next, val);
	}

	void insertFront(T val)
	{
		DNode* new_node = create_node(null, _first, val);
		_first = new_node;
		if (!_last)
			_last = _first;
	}

	DList opOpAssign(string op, Stuff)(Stuff rhs)
		if (op == "~" && is(typeof(insertBack(rhs))))
	{
		insertBack(rhs);
		return this;
	}

	void insertBack(T val)
	{
		DNode* new_node = create_node(_last, null, val);
		_last = new_node;
		if (!_first)
			_first = _last;
	}

	void popFront()
	{
		assert(_first);
		if (_last is _first)
			_last = null;
		_first = _first.next;
	}

	void popBack()
	{
		assert(_last);
		if (_last is _first)
			_first = null;
		_last = _last.prev;
	}
}

unittest
{
	DList!double l = DList!double();
	assert(l.empty);
	l.insertBack(1.0);
	assert(!l.empty);
	assert(l.front == 1.0);
	l.popBack();
	assert(l.empty);
}

unittest
{
	DList!double l = DList!double([1.0, 2.0]);
	assert(!l.empty);
	assert(l.back == 2.0);
	l.popBack();
	assert(!l.empty);
	assert(l.back == 1.0);
	l.popBack();
	assert(l.empty);
}

void removeAll(alias pred, T)(ref DList!T list)
{
	for (auto i = list.first; !i.end; i.next())
		if (unaryFun!pred(i.val))
			list.remove(i);
}

void removeAll(T)(ref DList!T list, scope bool delegate(T) pred)
{
	for (auto i = list.first; !i.end; i.next())
		if (pred(i.val))
			list.remove(i);
}

/// Remove all elements that satisfy pred and apply func to them
void removeAll(T)(ref DList!T list, scope bool delegate(T) pred,
	scope void delegate(ref T) func)
{
	for (auto i = list.first; !i.end; i.next())
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			func(i.val);
		}
}

bool removeFirst(alias pred, T)(ref DList!T list)
{
	for (auto i = list.first; !i.end; i.next())
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			return true;
		}
	return false;
}

bool removeFirst(T)(ref DList!T list, scope bool delegate(T) pred)
{
	for (auto i = list.first; !i.end; i.next())
		if (pred(i.val))
		{
			list.remove(i);
			return true;
		}
	return false;
}

import std.algorithm.comparison: equal;

unittest
{
	DList!int l = DList!int([1, 2, 3, 3, 4]);
	l.removeFirst!"a == 3";
	assert(equal(l[], [1, 2, 3, 4]));
	l.removeFirst!"a == 3";
	assert(equal(l[], [1, 2, 4]));
	l.removeFirst!(a => a == 2);
	assert(equal(l[], [1, 4]));
}

unittest
{
	DList!int l = DList!int([0, 1, 1, 2, 3, 3]);
	l.removeAll!"a == 3";
	assert(equal(l[], [0, 1, 1, 2]));
	l.removeAll!(a => a == 1);
	assert(equal(l[], [0, 2]));
}
