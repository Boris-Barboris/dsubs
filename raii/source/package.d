module raii;

import raii.containers.dlist;

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

    alias Delegate = raii.closure.AllocationContext!(Allocator, Atomic).Delegate;

    alias autodlg = raii.closure.AllocationContext!(Allocator, Atomic).autodlg;

    template DList(T)
    {
        alias DList = raii.containers.dlist.DList!(T, Allocator);
    }
}

void main(){}
