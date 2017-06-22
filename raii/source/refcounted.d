module raii.refcounted;

import core.atomic: atomicOp;
import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;
import std.traits;

import raii.utils;

// Reference-counted sharable memory owner.
struct RefCounted(T, bool Atomic = true, Allocator = Mallocator)
    if (isAllocator!Allocator && !isArray!T)
{
    enum HoldsAllocator = !isStaticAllocator!Allocator;

    static if (is(T == class) || is(T == interface))
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

    static if (Atomic)
        alias RefCounterT = shared size_t;
    else
        alias RefCounterT = size_t;

    private RefCounterT* refcount;
    private PtrT ptr;

    static if (HoldsAllocator)
        private Allocator allocator;

    @property bool valid() @nogc { return (*refcount > 0); }

    @disable this();

    // don't generate constructors for abstract types
    static if (!(is(T == interface) || isAbstractClass!(T)))
    {
        static if (!HoldsAllocator)
        {
            private this(PtrT ptr)
            {
                this.refcount = cast(RefCounterT*) Allocator.instance.make!size_t(1);
                this.ptr = ptr;
            }

            static RefCounted!(T, Atomic, Allocator)
            make(Args...)(auto ref Args args)
            {
                auto ptr = Allocator.instance.make!(T)(forward!args);
                auto rq = RefCounted!(T, Atomic, Allocator)(ptr);
                assert(rq.valid);
                return rq;
            }
        }
        else
        {
            private this(PtrT ptr, Allocator alloc)
            {
                this.refcount = cast(RefCounterT*) alloc.make!size_t(1);
                this.ptr = ptr;
                this.allocator = alloc;
            }

            static RefCounted!(T, Atomic, Allocator)
            make(Args...)(auto ref Allocator alloc, auto ref Args args)
            {
                auto ptr = alloc.make!(T)(forward!args);
                auto rq = RefCounted!(T, Atomic, Allocator)(ptr, alloc);
                assert(rq.valid);
                return rq;
            }
        }
    }

    ~this()
    {
        decrement();
    }

    // destroy the resource (destructor + free memory)
    private void destroy()
    {
        static if (HoldsAllocator)
            allocator.dispose(ptr);
        else
            Allocator.instance.dispose(ptr);
    }

    private void decrement()
    {
        assert(valid);
        static if (Atomic)
            atomicOp!"-="(*refcount, 1);
        else
            *refcount -= 1;
        if (*refcount == 0)
            destroy();
    }

    private void increment()
    {
        assert(valid);
        static if (Atomic)
            atomicOp!"+="(*refcount, 1);
        else
            *refcount += 1;
    }

    this(this)
    {
        increment();
    }

    // handle polymorphism
    static if (is(T == class) || is(T == interface))
    {
        // Polymorphism-aware assign operator
        ref RefCounted!(T, Atomic, Allocator)
        opAssign(DT)(RefCounted!(DT, Atomic, Allocator) rhs)
        {
            decrement();
            this.ptr = rhs.ptr;
            this.refcount = rhs.refcount;
            static if (HoldsAllocator)
                this.allocator = rhs.allocator;
            increment();
            return this;
        }

        // Polymorphism-aware constructor
        this(DT)(RefCounted!(DT, Atomic, Allocator) rhs)
        {
            this.ptr = rhs.ptr;
            this.refcount = rhs.refcount;
            static if (HoldsAllocator)
                this.allocator = rhs.allocator;
            increment();
        }

        // Polymorphic downcast
        RefCounted!(BT, Atomic, Allocator) to(BT)()
            if ((is(BT == class) || is(BT == interface)) && isAssignable!(BT, T))
        {
            assert(valid);
            RefCounted!(BT, Atomic, Allocator) rv =
                RefCounted!(BT, Atomic, Allocator)(this);
            assert(rv.valid);
            return rv;
        }
    }
    else
    {
        ref opAssign(RefCounted!(T, Atomic, Allocator) rhs)
        {
            decrement();
            this.ptr = rhs.ptr;
            this.refcount = rhs.refcount;
            static if (HoldsAllocator)
                this.allocator = rhs.allocator;
            increment();
            return this;
        }
    }
}

unittest
{
    auto uq = RefCounted!int.make(5);
    assert(uq.valid);
    assert(uq.v == 5);
    uq.v = 7;
    assert(uq.v == 7);
}

unittest
{
    auto create()
    {
        return RefCounted!int.make(0);
    }
    void consume(RefCounted!int u)
    {
        assert(u.valid);
        assert(*u.refcount == 2);
        assert(u.v == 5);
    }
    auto u = create();
    assert(u.valid);
    assert(*u.refcount == 1);
    assert(u.v == 0);
    u.v = 5;
    consume(u);
    assert(*u.refcount == 1);
}

unittest
{
    struct TS
    {
        int x = -3;
    }
    auto u = RefCounted!TS.make;
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
    auto u1 = RefCounted!TC.make;
    assert(count == 1);
    {
        auto u2 = RefCounted!TC.make;
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
        u2 = u1;
        assert(count == 1);
        assert(u1.valid);
        assert(u2.valid);
        assert(*(u1.refcount) == 2);
    }
    assert(count == 1);
    assert(*(u1.refcount) == 1);
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
    alias Uq = RefCounted!(TC, true, Alloc*);
    auto u1 = Uq.make(&al);
    assert(count == 1);
    {
        auto u2 = Uq.make(&al);
        assert(count == 2);
        assert(u2.v !is null);
        assert(u2.v.j == 3);
        u2 = u1;
        assert(count == 1);
        assert(u1.valid);
        assert(u2.valid);
        assert(*(u1.refcount) == 2);
    }
    assert(count == 1);
    assert(*(u1.refcount) == 1);
    assert(total == 2);
}

unittest
{
    static int ades = 0;
    static int bdes = 0;
    class A { ~this() {ades++;}}
    class B: A { ~this(){bdes++;}}
    {
        RefCounted!A ag = RefCounted!A.make();
        {
            RefCounted!A aq = ag;
            assert(aq.valid && ag.valid);
            {
                RefCounted!A bq = RefCounted!B.make();
                assert(ades == 0);
                assert(bdes == 0);
            }
            assert(ades == 1);
            assert(bdes == 1);
        }
        assert(ades == 1);
        assert(bdes == 1);
    }
    assert(ades == 2);
    assert(bdes == 1);
}

unittest
{
    static int ades = 0;
    static int bdes = 0;
    class A { ~this() {ades++;}}
    class B: A { ~this(){bdes++;}}
    void consume(RefCounted!A uq)
    {
        assert(uq.valid);
    }
    {
        RefCounted!B aq = RefCounted!B.make();
        consume(aq.to!A);
        assert(ades == 0);
        assert(bdes == 0);
    }
    assert(ades == 1);
    assert(bdes == 1);
}
