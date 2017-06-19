// RAII memes

module dsubs_common.memory.box;

import std.traits;

import dsubs_common.containers.dlist;
import dsubs_common.memory.allocation;

// Essentially, Uniqueptr-alike scope-lived heap-allocated entity.
// Is not a proxy for contained object, use explicit val accessor.
struct Box(T, bool Weaks = false, alias newfunc = _new, alias deletefunc = _delete)
{
	alias BoxType = Box!(T, Weaks, newfunc, deletefunc);

	static if (is(T == class))
	{
		alias RefT = T;
		T val()
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

	@property bool empty() { return (_value is null); }

	// bread and butter
	~this()
	{
		dispose();
	}

	void dispose()
	{
		if (!empty)
		{
			static if (Weaks)
				deletefunc(pool);
			deletefunc(_value);
		}
	}

	// Carefull, make sure val is allocated by the same allocator
	this(RefT val)
	{
		_value = val;
		static if (Weaks)
			pool = newfunc!WeakCollector;
	}

	@disable this();

	// move operation
	ref BoxType opAssign(ref BoxType s)
	{
		dispose();
		_value = s._value;
		s._value = null;
		static if (Weaks)
		{
			pool = s.pool;
			s.pool = null;
		}
		return this;
	}

	static if (isArray!T)
	{
		this(size_t size)
		{
			_value = newfunc!(T)(size);
			assert(_value !is null);
			static if (Weaks)
				pool = newfunc!WeakCollector;
		}
	}
	else
	{
		this(Args...)(Args args)
		{
			_value = newfunc!(T, Args)(args);
			assert(_value !is null);
			static if (Weaks)
				pool = newfunc!WeakCollector;
		}

		static BoxType make()
		{
			BoxType res = BoxType(newfunc!(T)());
			return res;
		}
	}

	static if (Weaks)
	{
		alias Cleaner = void delegate();
		alias CleanerCollection = DList!Cleaner;

		// struct that manages delegates that implement weak reference
		// cleanup.
		private static struct WeakCollector
		{
			// cleanup routines are stored here
			private CleanerCollection dlgs;

			@disable this(this);

			CleanerCollection.Iterator register_cleanup(void delegate() dlg)
			{
				dlgs.insertBack(dlg);
				return dlgs.end;
			}

			void unregister_cleanup(CleanerCollection.Iterator iter)
			{
				dlgs.remove(iter);
			}

			~this()
			{
				foreach (dlg; dlgs)
					dlg();
			}
		}

		private WeakCollector* pool;

		// Struct that may be destroyed any moment
		static struct Weak
		{
			@disable this();

			this(ref BoxType box)
			{
				poolptr = box.pool;
				_value = box._value;
			}

			ref WeakCollector pool() { return *poolptr; }

			// pointer to collector pool
			private WeakCollector* poolptr = null;

			// copy of the pointer held by the main box
			private RefT _value = null;

			static if (is(T == class))
			{
				T val()
				{
					return _value;
				}
			}
			else
			{
				ref T val()
				{
					return *_value;
				}
			}
		}

		Weak weak() { return Weak(this); }
	}
}

template WBox(T, alias newfunc = _new, alias deletefunc = _delete)
{
	alias WBox = Box!(T, true, newfunc, deletefunc);
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

// Structs do not have identity, unfortunately.
// We cannot rely on this in constructor,
// nor can we rely on postblit. Stack-aware RAII cannot be implemented
// using structs.
unittest
{
	static void* constructPtr;
	static void* postblitPtr;
	static void* assignPtr;
	static void* rhsAssignPtr;

	void clear_ptrs()
	{
		constructPtr = postblitPtr = assignPtr = rhsAssignPtr = null;
	}

	struct TestStruct
	{
		this(bool f)
		{
			constructPtr = &this;
		}
		this(this)
		{
			postblitPtr = &this;
		}
		ref TestStruct opAssign(ref TestStruct s)
		{
			assignPtr = &this;
			rhsAssignPtr = &s;
			return this;
		}
		ref TestStruct opAssign(TestStruct s)
		{
			assignPtr = &this;
			return this;
		}
	}

	TestStruct testFunc()
	{
		return TestStruct(true);
	}
	TestStruct s = testFunc();
	assert(constructPtr);
	assert(!postblitPtr);
	assert(!assignPtr);
	assert(!rhsAssignPtr);
	assert(cast(void*) &s != constructPtr);		// I can't register pointer to s :(

	clear_ptrs();
	void testFun2(ref TestStruct s)
	{
		s = TestStruct(true);
	}
	testFun2(s);
	assert(constructPtr);
	assert(!postblitPtr);
	assert(assignPtr);
	assert(!rhsAssignPtr);
	assert(cast(void*) &s == assignPtr);	// ok, at least I have this
	assert(cast(void*) &s != constructPtr);	// some internal pointer from tesstFun2 stack?

	clear_ptrs();
	static void* internal_ptr;
	TestStruct testFunc2()
	{
		TestStruct tt = TestStruct(true);
		assert(cast(void*) &tt == constructPtr);	// OK
		internal_ptr = &tt;
		return tt;
	}
	TestStruct s3 = testFunc2();
	assert(constructPtr);
	assert(!postblitPtr);
	assert(!assignPtr);		// is it RVO?...
	assert(!rhsAssignPtr);
	assert(cast(void*) &s3 == constructPtr);		// as expected
	assert(cast(void*) &s3 == internal_ptr);		// ... yes it is RVO

	clear_ptrs();
	TestStruct* s1 = new TestStruct(true);
	assert(constructPtr);
	assert(!postblitPtr);
	assert(!assignPtr);
	assert(!rhsAssignPtr);
	assert(cast(void*) s1 == constructPtr);		// ok

	constructPtr = postblitPtr = assignPtr = null;
	TestStruct* s2 = new TestStruct(true);

	clear_ptrs();
	*s1 = *s2;
	assert(!constructPtr);
	assert(!postblitPtr);
	assert(assignPtr);
	assert(rhsAssignPtr);
	assert(cast(void*) s1 == assignPtr);
	assert(cast(void*) s2 == rhsAssignPtr);

	clear_ptrs();
	*s1 = TestStruct(true);
	assert(constructPtr);
	assert(!postblitPtr);
	assert(assignPtr);
	assert(!rhsAssignPtr);
	assert(cast(void*) s1 != constructPtr);
	assert(cast(void*) s1 == assignPtr);

	clear_ptrs();
	void testFun3(TestStruct ts)
	{
		TestStruct ls = ts;
		assert(constructPtr);
		assert(postblitPtr);
		assert(!assignPtr);
		assert(!rhsAssignPtr);
		assert(cast(void*) &ls != constructPtr);
		assert(cast(void*) &ts != constructPtr);
		assert(cast(void*) &ls == postblitPtr);
	}
	testFun3(TestStruct(true));

	clear_ptrs();
	void testFun4(TestStruct ts)
	{
		TestStruct ls = ts;
		assert(!constructPtr);
		assert(postblitPtr);
		assert(!assignPtr);
		assert(!rhsAssignPtr);
		assert(cast(void*) &ls == postblitPtr);
	}
	testFun4(*s1);

	clear_ptrs();
	void testFun5(ref TestStruct ts)
	{
		TestStruct ls = ts;
		assert(!constructPtr);
		assert(postblitPtr);
		assert(!assignPtr);
		assert(!rhsAssignPtr);
		assert(cast(void*) &ls == postblitPtr);
	}
	testFun5(s);
}

unittest
{
	static int res;
	static int res2;
	static int res3;
	assert(res == 0);
	struct TestStruct
	{
		this(int xx) { x = xx; }
		int x;
		~this() { res = -3; }
	}
	{
		auto t = WBox!TestStruct(2);
		alias WeakT = typeof(t).Weak;
		assert(!t.empty);
		assert(t.val.x == 2);
		assert(t.pool.dlgs.empty);
		{
			WeakT w = t.weak();
			assert(t.pool.dlgs.empty);
			assert(w.val.x == 2);
			w.val.x = 4;
			assert(w.val.x == 4);
			auto iter = w.pool.register_cleanup(() {res2 = 6;});
			auto iter2 = w.pool.register_cleanup(() {res3 = 4;});
			scope(exit) w.pool.unregister_cleanup(iter2);
		}
		assert(res == 0);
		assert(res2 == 0);
		assert(res3 == 0);
		assert(t.val.x == 4);
	}
	assert(res == -3);
	assert(res2 == 6);
	assert(res3 == 0);
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
