module dsubs_common.containers.dlist;

public import std.container.dlist;

import std.functional : unaryFun;
import std.range: take;

void removeRangeHead(T)(ref DList!T list, DList!T.Range r)
{
	list.stableLinearRemove(take(r, 1));
}

void removeRangeTail(T)(ref DList!T list, DList!T.Range r)
{
	list.stableLinearRemove(take(r, 1));
}

void removeAll(alias pred, T)(ref DList!T list)
{
	for (auto r = list[]; !r.empty; r.popFront())
		if (unaryFun!pred(r.front))
			list.stableLinearRemove(take(r, 1));
}

void removeAll(T)(ref DList!T list, bool delegate(T) pred)
{
	for (auto r = list[]; !r.empty; r.popFront())
		if (pred(r.front))
			list.stableLinearRemove(take(r, 1));
}

/// Remove all elements that satisfy pred and apply func to them
void removeAll(T)(ref DList!T list, bool delegate(T) pred, void delegate(ref T) func)
{
	for (auto r = list[]; !r.empty; r.popFront())
		if (unaryFun!pred(r.front))
		{
			list.stableLinearRemove(take(r, 1));
			func(r.front);
		}
}

T* removeFirst(alias pred, T)(ref DList!T list)
{
	for (auto r = list[]; !r.empty; r.popFront())
		if (unaryFun!pred(r.front))
		{
			list.stableLinearRemove(take(r, 1));
			return &r.front();
		}
	return null;
}

T* removeFirst(T)(ref DList!T list, bool delegate(T) pred)
{
	for (auto r = list[]; !r.empty; r.popFront())
		if (pred(r.front))
		{
			list.stableLinearRemove(take(r, 1));
			return &r.front();
		}
	return null;
}

import std.algorithm.comparison: equal;

unittest
{
	DList!int l = DList!int([1, 2, 3, 3, 4]);
	l.removeFirst!"a == 3";
	assert(equal(l[], [1, 2, 3, 4]));
	l.removeFirst!"a == 3";
	assert(equal(l[], [1, 2, 4]));
	l.removeFirst!(a => a == 2);
	assert(equal(l[], [1, 4]));
}

unittest
{
	DList!int l = DList!int([0, 1, 1, 2, 3, 3]);
	l.removeAll!"a == 3";
	assert(equal(l[], [0, 1, 1, 2]));
	l.removeAll!(a => a == 1);
	assert(equal(l[], [0, 2]));
}
