module dsubs_client.core.utils;

import std.algorithm;
import std.range;

import dsubs_client.containers.dlist;

unittest
{
	DList!int list = [1, 3, 1, 4];
	list.removePred(a => a == 1);
	assert(equal(list[], [3, 4]));
}
