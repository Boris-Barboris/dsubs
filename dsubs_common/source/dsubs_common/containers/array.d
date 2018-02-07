module dsubs_common.containers.array;

import std.functional : unaryFun;

/// removes first element wich satisfies predicate 'pred' in array 'arr',
/// returns true if it was found.
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

/// removes first occurence of 'el' in array 'arr', returns true if
/// it was found. This version uses 'is' comparator.
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

/// removes first occurence of 'el' in array 'arr', returns true if
/// it was found. This version uses 'is' comparator, and does not preserve
/// element order.
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
