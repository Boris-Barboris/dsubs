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

    auto autodlg(ExArgs...)(ExArgs exargs)
    {
        static if (isStaticAllocator!Allocator)
            enum f_idx = 0;
        else
        {
            static assert(isAllocator!(ExArgs[0]));
            enum f_idx = 1;
        }
        static assert(ExArgs.length > f_idx);
        static assert(isFunctionPointerType!(ExArgs[f_idx]));

        alias RetType = DecomposeFunction!(ExArgs[f_idx]).RetType;
        alias AllArgs = DecomposeFunction!(ExArgs[f_idx]).ArgTypes;

        static assert(AllArgs.length >= (ExArgs.length - 1 - f_idx));
        enum int dlgArgCount = AllArgs.length - ExArgs.length + 1 + f_idx;
        alias DlgArgs = Take!(dlgArgCount, AllArgs);
        alias CapturedArgs = Skip!(dlgArgCount, AllArgs);

        // specific closure class
        static class CClosure: Closure!(RetType, DlgArgs)
        {
            private RetType function(AllArgs) _f;
            mixin(FieldExpand!CapturedArgs);
            this(RetType function(AllArgs) f, CapturedArgs cpt)
            {
                _f = f;
                foreach (i, field; CapturedArgs)
                {
                    mixin("field" ~ to!string(i)) = cpt[i];
                }
            }

            override RetType call(DlgArgs args)
            {
                static if (CapturedArgs.length > 0)
                {
                    enum string captee_fields = enumerateFields(CapturedArgs.length);
                    return _f(forward!args, mixin(captee_fields));
                }
                else
                    return _f(forward!args);
            }
        }

        CtxRefCounted!(Closure!(RetType, DlgArgs)) rfc =
            CtxRefCounted!(CClosure).make(exargs);
        Delegate!(RetType, DlgArgs) dlg = Delegate!(RetType, DlgArgs)(rfc);
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

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(void);
    Dlg d = Ctx.autodlg((){});
    d();
}

unittest
{
    alias Ctx = AllocationContext!(Mallocator, true);
    alias Dlg = Ctx.Delegate!(int, int, float);
    Dlg d = Ctx.autodlg((int x, float y){ return 3;});
    d(4, 4.0f);
}

import std.experimental.allocator.showcase;

unittest
{
    alias AllocType = StackFront!(4096, Mallocator);
    AllocType al;
    alias Ctx = AllocationContext!(AllocType*, true);
    alias Dlg = Ctx.Delegate!(int, int, float);
    Dlg d = Ctx.autodlg(&al, (int x, float y){ return 3;});
    d(4, 4.0f);
}
