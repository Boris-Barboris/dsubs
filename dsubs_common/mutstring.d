module mutstring;

import std.algorithm.comparison;
import std.string;

/// Alias for simple mutable ASCII string, that we all need so much 
/// in gaming in order to prevent excessive allocations.
alias mutstring = char[];

/// Creates mutstring from string
mutstring _s(string s) nothrow pure
{
	auto raw_str = toStringz(s);
	size_t len = s.length;
	mutstring res = new char[len + 1];
	for (size_t i = 0; i < len; i++)
		res[i] = *(raw_str + i);
	res[len] = cast(char)(0);
	return res;
}

/// Creates mutstring from string, while also
/// explicitly setting expected max string length.
mutstring _s(string s, size_t size) nothrow pure
{
	auto raw_str = toStringz(s);
	size_t len = max(s.length, size);
	mutstring res = new char[len + 1];
	for (size_t i = 0; i < len; i++)
		res[i] = *(raw_str + i);
	res[len] = cast(char)(0);
	return res;
}


nothrow unittest
{
	mutstring s = _s("asdf");
	assert(s[0] == 'a');
	assert(s[3] == 'f');
	assert(s[4] == 0);
	assert(indexOf(s, 'd') == 2);
	assert(indexOf(s, 'x') == -1);
}

nothrow unittest
{
	mutstring s = _s("foobar", 20);
	assert(s.length == 21);
}