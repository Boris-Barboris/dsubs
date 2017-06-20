module raii.containers.array;

import std.experimental.allocator: make, dispose;
import std.experimental.allocator.mallocator: Mallocator;
import std.functional : unaryFun;

import raii.utils;

struct Array(T, Allocator: Mallocator)
    if (isAllocator!Allocator)
{
    static struct Data
    {
        size_t length;
        T[] arr;

        @disable this();
    }
}
