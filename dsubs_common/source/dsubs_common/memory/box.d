// RAII memes

module dsubs_common.memory.box;

import std.traits;

import dsubs_common.memory.allocation;

// Essentially, scope-lived heap-allocated entity
struct Box(T)
{
	static if (is(T == class) || isArray!T)
	{
		alias RefT = T;
		ref T val() { return _value; }
	}
	else
	{
		alias RefT = T*;
		ref T val() { return *_value; }
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
			_delete(_value);
	}

	this(RefT val)
	{
		_value = val;
	}

	static if (isArray!T)
	{
		this(size_t size)
		{
			_value = _new!(T)(size);
			assert(_value !is null);
		}
	}
	else
	{
		this(Args...)(Args args)
		{
			_value = _new!(T, Args)(args);
			assert(_value !is null);
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
		auto t = Box!TestStruct(new TestStruct);
		assert(!t.empty);
		t.val.y = 4;
		assert(t._value.y == 4);
	}
	assert(res == -3);
}
