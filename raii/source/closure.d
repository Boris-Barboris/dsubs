module raii.closure;

import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;
import std.traits;

import raii.refcounted;
import raii.utils;

abstract class Closure(Ret, Args...)
{
    Ret call(Args args);
}

template AllocationContext(Allocator = Mallocator, bool Atomic = true)
{
    struct Delegate(Ret, Args...)
    {
        @disable this();

        package this(RefCounted!(Closure!(Ret, Args), Atomic, Allocator) clos)
        {
            closure = clos;
        }

        package RefCounted!(Closure!(Ret, Args), Atomic, Allocator) closure;

        Ret opCall(Args args)
        {
            return closure.v.call(forward!args);
        }
    }
}

unittest
{
    alias Dlg = AllocationContext!(Mallocator, true).Delegate!(void, int);
    static int counter = 0;
    static int ccount = 0;
    class CClosure: Closure!(void, int)
    {
        this() { ccount++; }
        ~this() { ccount--; }
        override void call(int v) { counter++; }
    }
    {
        RefCounted!(Closure!(void, int)) rfc = RefCounted!CClosure.make;
        Dlg dlg = Dlg(rfc);
        dlg(3);
        dlg(-1);
        assert(counter == 2);
        assert(ccount == 1);
    }
    assert(ccount == 0);
}
