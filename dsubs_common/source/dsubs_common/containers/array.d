module dsubs_common.containers.array;

import std.functional : unaryFun;
import std.algorithm: equal;

@safe:

/// Remove first element wich satisfies predicate 'pred' in array 'arr'.
/// Returns true if it was found.
bool removeFirst(alias pred, T)(ref T[] arr)
{
	for (size_t i = 0; i < arr.length; i++)
		if (unaryFun!pred(arr[i]))
		{
			for (size_t j = i + 1; j < arr.length; j++)
				arr[j - 1] = arr[j];
			arr.length -= 1;
			return true;
		}
	return false;
}

/// Remove first occurence of 'el' in array 'arr'.
/// Returns true it was found. This version uses 'is' comparator.
bool removeFirst(T)(ref T[] arr, T el)
{
	for (size_t i = 0; i < arr.length; i++)
		if (arr[i] is el)
		{
			for (size_t j = i + 1; j < arr.length; j++)
				arr[j - 1] = arr[j];
			arr.length -= 1;
			return true;
		}
	return false;
}

unittest
{
	int[] a = [2, 3, 4];
	assert(a.removeFirst(3));
	assert(a.equal([2, 4]));
}

/// Remove first occurence of 'el' in array 'arr', return true if
/// it was found. This version uses 'is' comparator and does not preserve
/// element relative order.
bool removeFirstUnstable(T)(ref T[] arr, T el)
{
	for (size_t i = 0; i < arr.length; i++)
		if (arr[i] is el)
		{
			arr[i] = arr[$-1];
			arr.length -= 1;
			return true;
		}
	return false;
}

//size_t removeAll()
