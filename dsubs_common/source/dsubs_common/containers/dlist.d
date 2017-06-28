module dsubs_common.containers.dlist;

import std.functional : unaryFun;


// Double-linked list
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

		~this()
		{
			if (prev)
				prev.next = next;
			if (next)
				next.prev = prev;
		}
	}

	DNode* _first, _last;

	ref T front()
	{
		assert(!empty);
		return _first.val;
	}

	ref T back()
	{
		assert(!empty);
		return _last.val;
	}

	// DList is struct only because of VFT overhead
	@disable this(this);

	this(T[] range)
	{
		foreach (el; range)
			this.insertBack(el);
	}

	~this()
	{
		destroy_all();
	}

	private void destroy_all()
	{
		DNode* ptr = _first;
		while (ptr)
		{
			DNode* next = ptr.next;
			destroy_node(ptr);
			ptr = next;
		}
	}

	void clear()
	{
		destroy_all();
		_first = _last = null;
		assert(empty);
	}

	// Two-side iterator
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
		@property bool end() const { return _target == null; }
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
			return first._target.prev == last._target;
		}
		@property Range save() { return this; }
	}

	Range opSlice()
	{
		return Range(begin, end);
	}

	@property Iterator begin() { return Iterator(_first); }
	@property Iterator end() { return Iterator(_last); }

	enum MoveDir {
		FRWD,
		BACK,
	};

	// MoveDirection - wich way to move cursor after underlying node is
	// destroyed and deallocated.
	void remove(MoveDir md = MoveDir.FRWD)(ref Iterator cursor)
	{
		assert(!cursor.end);
		DNode* node = cursor._target;
		if (_first == node)
			_first = node.next;
		if (_last == node)
			_last = node.prev;
		static if (md == MoveDir.FRWD)
			cursor.next();
		else
			cursor.prev();
		destroy_node(node);
	}

	@property bool empty()
	{
		return _first == null;
	}

	DNode* create_node(DNode* prev, DNode* next, ref T val)
	{
		return new DNode(prev, next, val);
		/*
		static if (HoldsAllocator)
			return this._allocator.make!DNode(prev, next, val);
		else
			return Allocator.instance.make!DNode(prev, next, val);*/
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
		if (_last == _first)
			_last = null;
		auto todelete = _first;
		_first = _first.next;
		destroy_node(todelete);
	}

	void destroy_node(DNode* node)
	{
		assert(node);
		delete node;
		/*
		static if (HoldsAllocator)
			return this._allocator.dispose(node);
		else
			return Allocator.instance.dispose(node);*/
	}

	void popBack()
	{
		assert(_last);
		if (_last == _first)
			_first = null;
		auto todelete = _last;
		_last = _last.prev;
		destroy_node(todelete);
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
	for (auto i = list.begin; !i.end;)
		if (unaryFun!pred(i.val))
			list.remove(i);
		else
			i.next();
}

void removeAll(T)(ref DList!T list, scope bool delegate(T) pred)
{
	for (auto i = list.begin; !i.end;)
		if (pred(i.val))
			list.remove(i);
		else
			i.next();
}

/// Remove all elements that satisfy pred and apply func to them
void removeAll(T)(ref DList!T list, scope bool delegate(T) pred,
	scope void delegate(ref T) func)
{
	for (auto i = list.begin; !i.end;)
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			func(i.val);
		}
		else
			i.next();
}

bool removeFirst(alias pred, T)(ref DList!T list)
{
	for (auto i = list.begin; !i.end; i.next())
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			return true;
		}
	return false;
}

bool removeFirst(T)(ref DList!T list, scope bool delegate(T) pred)
{
	for (auto i = list.begin; !i.end; i.next())
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
