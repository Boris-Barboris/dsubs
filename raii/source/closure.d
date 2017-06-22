module raii.closure;

import std.conv: to;
import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional: forward;
import std.meta;
import std.traits;

import raii.refcounted;
import raii.utils;

abstract class Closure(Ret, Args...)
{
    Ret call(Args args);
}

template AllocationContext(Allocator = Mallocator, bool Atomic = true)
{
    template CtxRefCounted(T)
    {
        alias CtxRefCounted = RefCounted!(T, Atomic, Allocator);
    }

    struct Delegate(Ret, Args...)
    {
        @disable this();

        private this(CtxRefCounted!(Closure!(Ret, Args)) clos)
        {
            closure = clos;
        }

        private CtxRefCounted!(Closure!(Ret, Args)) closure;

        bool opEquals(ref Delegate!(Ret, Args) s)
        {
            return closure.v is s.closure.v;
        }

        bool opEquals(Delegate!(Ret, Args) s)
        {
            return closure.v is s.closure.v;
        }

        Ret opCall(Args args)
        {
            return closure.v.call(forward!args);
        }
    }

    template DecomposeFunction(FuncType)
    {
        alias RetType = RT;
        alias Args = Ar;
    }

    auto autodlg(ExArgs...)(ExArgs exargs)
        if (isFunction!(ExArgs[0]))
    {
        pragma(msg, ExArgs);
        alias RetType = DecomposeFunction!(ExArgs[0]).RetType;
        alias Args = DecomposeFunction!(ExArgs[0]).Args;
        pragma(msg, RetType);
        pragma(msg, Args);

        // first we need to learn Args, by removing Captured fron FuncArgs
        static class CClosure: Closure!(Ret, Args)
        {
            private Ret function(Args, Captured) _f;
            mixin(FieldExpand!Captured);
            this(Ret function(Args, Captured) f, Captured cpt)
            {
                _f = f;
                foreach (i, field; Captured)
                {
                    mixin("field" ~ to!string(i)) = cpt[i];
                }
            }

            override Ret call(Args args)
            {
                static if (Captured.length > 0)
                {
                    enum string captee_fields = enumerateFields(Captured.length);
                    return _f(forward!args, mixin(captee_fields));
                }
                else
                    return _f(forward!args);
            }
        }

        CtxRefCounted!(Closure!(Ret, Args)) rfc =
            CtxRefCounted!(CClosure).make(f, captee);
        Delegate!(Ret, Args) dlg = Delegate!(Ret, Args)(rfc);
        return dlg;
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

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(void, int);
    int sum = 0;
    int[] arr = [3, 5, 1, 9, 4];
    void map(int[] arr, Dlg dlg)
    {
        for (int i = 0; i < arr.length; i++)
            dlg(arr[i]);
    }
    Dlg d = Ctx.autodlg((int x, int* s) { *s += x; }, &sum);
    map(arr, d);
    assert(sum == 22);
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(int, int, int);
    int[] arr = [3, 5, 1, 9, 4];
    int reduce(D)(int[] arr, D dlg)
    {
        int res = dlg(arr[0], arr[1]);
        for (int i = 2; i < arr.length; i++)
            res = dlg(res, arr[i]);
        return res;
    }
    Dlg d = Ctx.autodlg((int x, int y) => x + y);
    int sum = reduce(arr, d);
    assert(sum == 22);
}
