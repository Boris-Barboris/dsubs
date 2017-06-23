module raii;

import raii.unique;
import raii.refcounted;
import raii.closure;
import raii.utils;

template AllocationContext(Allocator = Mallocator, bool Atomic = true)
    if (isAllocator!Allocator)
{
    template Unique(T)
    {
        alias Unique = raii.unique.Unique!(T, Allocator);
    }

    template RefCounted(T)
    {
        alias RefCounted = raii.refcounted.RefCounted!(T, Atomic, Allocator);
    }

    template Delegate(Ret, Args...)
    {
        alias Delegate = raii.closure.AllocationContext!(Allocator, Atomic).Delegate!(Ret, Args);
    }

    template autodlg(ExArgs...)
    {
        alias autodlg = raii.closure.AllocationContext!(Allocator, Atomic).autodlg!(ExArgs);
    }
}

void main(){}
