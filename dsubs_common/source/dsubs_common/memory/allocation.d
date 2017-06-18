module dsubs_common.memory.allocation;

import std.experimental.allocator;
import std.experimental.allocator.mallocator;
import std.traits;

// For now malloc should suffice. If perfrormance or fragmentation will
// be noticed, we'll use smarter allocation patterns
auto _new(T, Args...)(Args args)
{
	return Mallocator.instance.make!(T)(args);
}

T[] _new(T: T[])(size_t size)
{
	return makeArray!(T)(Mallocator.instance, size);
}

void _delete(T)(auto ref T p)
	if (isPointer!T || is(T == class) || isArray!T)
{
	Mallocator.instance.dispose(p);
	p = null;
}

unittest
{
	static int glob = 0;
	struct TestStruct
	{
		int x, y;
		~this() { glob = -3; }
	}
	TestStruct* t = _new!TestStruct;
	assert(t);
	t.x = 3;
	assert(t.x == 3);
	_delete(t);
	assert(t == null);
	assert(glob == -3);
}

unittest
{
	int[] arr = _new!(int[])(10);
	assert(arr.length == 10);
	_delete(arr);
	assert(arr is null);
}

unittest
{
	class TestClass
	{
		int a;
		static int b;
		this(int aval)
		{
			a = aval;
		}
		~this()
		{
			b = -1;
		}
	}
	TestClass t = _new!TestClass(2);
	assert(t.a == 2);
	_delete(t);
	assert(t is null);
	assert(TestClass.b == -1);
}
