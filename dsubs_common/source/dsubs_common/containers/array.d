module dsubs_common.containers.array;

import std.functional : unaryFun;

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

//size_t removeAll()
