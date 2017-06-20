module raii.unique;

import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;
import std.traits;

import raii.utils;

// Unique memory owner, holds one instance of type T. Don't use it to hold
// built-in arrays, use custom array type instead. Scope-based lifespan.
struct Unique(T, Allocator = Mallocator)
    if (isAllocator!Allocator && !isArray!T)
{
    enum HoldsAllocator = !isStaticAllocator!Allocator;

    static if (is(T == class))
    {
        alias PtrT = T;
        @property T v() @nogc
        {
            assert(valid);
            return ptr;
        }
    }
    else
    {
        alias PtrT = T*;
        @property ref T v() @nogc
        {
            assert(valid);
            return *ptr;
        }
    }

    private PtrT ptr;

    @property bool valid() @nogc { return ptr !is null; }

    @disable this();

    static if (!HoldsAllocator)
    {
        this(Args...)(auto ref Args args)
        {
            ptr = Allocator.instance.make!T(forward!args);
            assert(valid);
        }

        // ugly way to initialize internal type with it's default constructor
        private this(PtrT ptr)
        {
            this.ptr = ptr;
        }

        // factory function for types with parameterless constructors
        static Unique!(T, Allocator) make()
        {
            auto ptr = Allocator.instance.make!T;
            auto uq = Unique!(T, Allocator)(ptr);
            assert(uq.valid);
            return uq;
        }
    }
    else
    {
        private Allocator allocator;

        this(Args...)(auto ref Allocator alloc, auto ref Args args)
        {
            allocator = alloc;
            ptr = alloc.make!T(forward!args);
            assert(valid);
        }
    }

    // Initialize unique from another one with ownership transfer
    this(ref Unique!(T, Allocator) rhs) @nogc
    {
        assert(rhs.valid);
        this.ptr = rhs.ptr;
        rhs.ptr = null;
        static if (HoldsAllocator)
            this.allocator = rhs.allocator;
    }

    // move ownership to new rvalue Unique
    Unique!(T, Allocator) move()
    {
        auto rv = Unique!(T, Allocator)(this);
        assert(!valid);
        return rv;
    }

    ~this()
    {
        destroy();
    }

    // destroy the resource (destructor + free memory)
    void destroy()
    {
        if (valid)
        {
            static if (HoldsAllocator)
                allocator.dispose(ptr);
            else
                Allocator.instance.dispose(ptr);
            ptr = null;
        }
    }

    @disable this(this);

    @disable ref Unique!(T, Allocator) opAssign(Unique!(T, Allocator) rhs);

    ref opAssign(ref Unique!(T, Allocator) rhs)
    {
        destroy();
        this.ptr = rhs.ptr;
        rhs.ptr = null;
        static if (HoldsAllocator)
            this.allocator = rhs.allocator;
        return this;
    }
}

unittest
{
    auto uq = Unique!int(5);
    assert(uq.valid);
    assert(uq.v == 5);
    uq.v = 7;
    assert(uq.v == 7);
}

unittest
{
    auto create_uniq()
    {
        return Unique!int(0);
    }
    void consume_uniq(Unique!int u)
    {
        assert(u.valid);
        assert(u.v == 5);
    }
    auto u = create_uniq();
    assert(u.valid);
    assert(u.v == 0);
    u.v = 5;
    consume_uniq(u.move);
    assert(!u.valid);
}

unittest
{
    struct TS
    {
        int x = -3;
    }
    auto u = Unique!TS.make;
    assert(u.v.x == -3);
}

unittest
{
    static int count = 0;
    static int total = 0;
    class TC
    {
        this() { count++; total++; }
        ~this() { count--; }
        int j = 3;
    }
    auto u1 = Unique!TC.make;
    assert(count == 1);
    {
        auto u2 = Unique!TC.make;
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
        u2 = u1;
        assert(count == 1);
        assert(!u1.valid);
        assert(u2.valid);
    }
    assert(count == 0);
    assert(total == 2);
}

import std.experimental.allocator.showcase;

unittest
{
    static int count = 0;
    static int total = 0;
    class TC
    {
        this() { count++; total++; }
        ~this() { count--; }
        int j = 3;
    }
    alias Alloc = StackFront!(4096, Mallocator);
    Alloc al;
    alias Uq = Unique!(TC, Alloc*);
    auto u1 = Uq(&al);
    assert(count == 1);
    {
        auto u2 = Uq(&al);
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
        u2 = u1;
        assert(count == 1);
        assert(!u1.valid);
        assert(u2.valid);
    }
    assert(count == 0);
    assert(total == 2);
}
