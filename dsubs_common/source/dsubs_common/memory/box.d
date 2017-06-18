// RAII memes

module dsubs_common.memory.box;

import std.traits;

import dsubs_common.memory.allocation;

// Essentially, Uniqueptr-alike scope-lived heap-allocated entity.
// Is not a proxy for contained object, use explicit val accessor.
struct Box(T, alias newfunc = _new, alias deletefunc = _delete)
{
	static if (is(T == class) || isArray!T)
	{
		alias RefT = T;
		ref T val()
		{
			assert(!this.empty);
			return _value;
		}
	}
	else
	{
		alias RefT = T*;
		ref T val()
		{
			assert(!this.empty);
			return *_value;
		}
	}

	private RefT _value = null;		// contained resource

	// give away ownership
	RefT release()
	{
		RefT v = _value;
		_value = null;
		return v;
	}

	@property bool empty() { return (_value is null); }

	// bread and butter
	~this()
	{
		if (!empty)
			deletefunc(_value);
	}

	// Carefull, make sure val is allocated by the same allocator
	this(RefT val)
	{
		_value = val;
	}

	@disable this();

	// move operation
	ref Box!T opAssign(ref Box!T s)
	{
		if (!empty)
			deletefunc(_value);
		_value = s.release();
		return this;
	}

	static if (isArray!T)
	{
		this(size_t size)
		{
			_value = newfunc!(T)(size);
			assert(_value !is null);
		}
	}
	else
	{
		this(Args...)(Args args)
		{
			_value = newfunc!(T, Args)(args);
			assert(_value !is null);
		}

		static Box!T make()
		{
			Box!T res = Box!T(newfunc!(T)());
			return res;
		}
	}
}

unittest
{
	auto i = Box!int(3);
	assert(i.val == 3);
	assert(!i.empty);
}

unittest
{
	static int res;
	struct TestStruct
	{
		int y;
		~this() { res = -3; }
	}
	{
		auto t = Box!TestStruct.make;
		assert(!t.empty);
		t.val.y = 4;
		assert(t._value.y == 4);
	}
	assert(res == -3);
}

unittest
{
	static int res = 0;
	struct TestStruct
	{
		~this() { res = -1; }
	}
	Box!TestStruct getBox()
	{
		return Box!TestStruct.make;
	}
	{
		auto i = getBox();
		assert(res == 0);
	}
	assert(res == -1);
}
