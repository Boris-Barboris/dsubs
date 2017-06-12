module dsubs_common.containers.dlist;

import std.functional : unaryFun;

struct DList(T)
{
	struct DNode
	{
		DNode* prev;
		DNode* next;
		T val;

		this(DNode* p, DNode* n, T v)
		{
			prev = p;
			next = n;
			val = v;
			if (p)
				p.next = &this;
			if (n)
				p.prev = &this;
		}
	}

	DNode* _first;
	DNode* _last;

	this(T[] range)
	{
		foreach (el; range)
			this.insertBack(el);
	}

	struct Iterator
	{
		DNode* _target;
		this(DNode* tgt) { _target = tgt; }
		ref T val()
		{
			assert(!this.end, "Iterator is outside of DList");
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
		bool end() const { return _target == null; }
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
		return Range(begin(), end());
	}

	Iterator begin() { return Iterator(_first); }
	Iterator end() { return Iterator(_last); }

	void remove(Iterator cursor)
	{
		DNode* node = cursor._target;
		if (node.prev)
			node.prev.next = node.next;
		if (node.next)
			node.next.prev = node.prev;
		if (_first == node)
			_first = node.next;
		if (_last == node)
			_last = node.prev;
	}

	bool empty()
	{
		return _first == null;
	}

	void insertFront(T val)
	{
		DNode* new_node = new DNode(null, _first, val);
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
		DNode* new_node = new DNode(_last, null, val);
		_last = new_node;
		if (!_first)
			_first = _last;
	}

	T popFront()
	{
		assert(_first);
		T val = _first.val;
		if (_last == _first)
			_last = null;
		_first = _first.next;
		return val;
	}

	T popBack()
	{
		assert(_last);
		T val = _last.val;
		if (_last == _first)
			_first = null;
		_last = _last.prev;
		return val;
	}
}

unittest
{
	DList!double l = DList!double();
	assert(l.empty);
	l.pushBack(1.0);
	assert(!l.empty);
	assert(l.popBack() == 1.0);
	assert(l.empty);
}

unittest
{
	DList!double l = DList!double([1.0, 2.0]);
	assert(!l.empty);
	assert(l.popBack() == 2.0);
	assert(!l.empty);
	assert(l.popBack() == 1.0);
	assert(l.empty);
}

void removeAll(alias pred, T)(ref DList!T list)
{
	for (auto i = list.begin; !i.end; i.next())
		if (unaryFun!pred(i.val))
			list.remove(i);
}

void removeAll(T)(ref DList!T list, bool delegate(T) pred)
{
	for (auto i = list.begin; !i.end; i.next())
		if (pred(i.val))
			list.remove(i);
}

/// Remove all elements that satisfy pred and apply func to them
void removeAll(T)(ref DList!T list, bool delegate(T) pred, void delegate(ref T) func)
{
	for (auto i = list.begin; !i.end; i.next())
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			func(i.val);
		}
}

T* removeFirst(alias pred, T)(ref DList!T list)
{
	for (auto i = list.begin; !i.end; i.next())
		if (unaryFun!pred(i.val))
		{
			list.remove(i);
			return &i.val();
		}
	return null;
}

T* removeFirst(T)(ref DList!T list, bool delegate(T) pred)
{
	for (auto i = list.begin; !i.end; i.next())
		if (pred(i.val))
		{
			list.remove(i);
			return &i.val();
		}
	return null;
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
