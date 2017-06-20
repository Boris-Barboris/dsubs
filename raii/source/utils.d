module raii.utils;

import std.experimental.allocator: make, dispose;
import std.traits: Unqual;

template isAllocator(T)
{
    private template isAllocatorAlike(T)
    {
        enum isAllocatorAlike = is(typeof(()
            {
                T allocator;
                int* i = allocator.make!int;
                allocator.dispose(i);
                void[] bytes = allocator.allocate(size_t.init);
                bool res = allocator.deallocate(bytes);
            }));
    }
    enum isAllocator = isAllocatorAlike!(Unqual!T) ||
        isAllocatorAlike!(shared Unqual!T);
}

template isStaticAllocator(T)
    if (isAllocator!T)
{
    static if (is(typeof(T.instance)))
        enum isStaticAllocator = isAllocator!(typeof(T.instance));
    else
        enum isStaticAllocator = false;
}

unittest
{
    import std.experimental.allocator.showcase: StackFront;
    import std.experimental.allocator.mallocator: Mallocator;

    static assert (isAllocator!Mallocator);
    static assert (isStaticAllocator!Mallocator);
    static assert (!isAllocator!int);
    static assert (isAllocator!(StackFront!4096));
}
