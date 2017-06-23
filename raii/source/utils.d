module raii.utils;

import std.conv: to;
import std.experimental.allocator: make, dispose;
import std.traits: Unqual, isArray;
import std.meta;

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

package string FieldExpand(FieldTypes...)()
{
    string result = "";
    foreach (i, field; FieldTypes)
        result ~= field.stringof ~ " field" ~ to!string(i) ~ ";";
    return result;
}

package string enumerateFields(uint count)
{
    string result = "";
    for (uint i = 0; i < count; i++)
    {
        result ~= "field" ~ to!string(i);
        if (i < count - 1)
            result ~= ", ";
    }
    return result;
}

template isFunctionPointerType(T: FT*, FT)
{
    enum isFunctionPointerType = is(FT == function);
}

unittest
{
    auto p = (){};
    static assert(isFunctionPointerType!(typeof(p)));
}

template DecomposeFunction(FuncType: FT*, FT)
    if (isFunctionPointerType!FuncType)
{
    static if (is(FT Params == function))
        alias ArgTypes = Params;
    else
        static assert(0);
    static if (is(FT RT == return))
        alias RetType = RT;
    else
        static assert(0);
}

unittest
{
    auto p = (int x){ return x; };
    static assert(is(DecomposeFunction!(typeof(p)).RetType == int));
    static assert(is(DecomposeFunction!(typeof(p)).ArgTypes == AliasSeq!int));
}

template Take(int count, T...)
{
    alias Take = T[0 .. count];
}

unittest
{
    alias res = Take!(2, int, int, int, float);
    static assert(is(res == AliasSeq!(int, int)));
    static assert(!is(res == AliasSeq!(int, float)));
}

template Skip(int count, T...)
{
    alias Skip = T[count .. $];
}

unittest
{
    alias res = Skip!(2, int, int, int, float);
    static assert(is(res == AliasSeq!(int, float)));
}

package string[] RemoveTail(string[] AllArgs, string[] TailArgs)()
{
    enum size_t rem_length = AllArgs.length - TailArgs.length;
    string[] res = AllArgs[0 .. rem_length];
    return res;
}
