module mutstring;

import std.algorithm.comparison;
import std.string;

/// Alias for simple mutable ASCII string, that we all need so much 
/// in gaming in order to prevent excessive allocations.
alias mutstring = char[];

/// Creates mutstring from string
mutstring _s(string s) nothrow pure @safe
{
	size_t len = s.length;
	mutstring res = new char[len + 1];
	for (size_t i = 0; i < len; i++)
		res[i] = s[i];
	res[len] = 0;
	return res;
}

/// Creates mutstring from string, allocating not less than size + 1 bytes
mutstring _s(string s, size_t size) nothrow pure @safe
{
	size_t len = max(s.length, size);
	mutstring res = new char[len + 1];
	for (size_t i = 0; i < s.length; i++)
		res[i] = s[i];
	res[s.length] = 0;
	return res;
}

/// Copy string contents into mutstring, extending it if
/// required.
void str2mut_copy(string s, ref mutstring ms) nothrow @safe
{
	if (s.length > ms.length - 1)
		ms.length = s.length + 1;
	foreach (i, c; s)
		ms[i] = c;
	ms[s.length] = 0;
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

nothrow unittest
{
	mutstring s = _s("aabb");
	str2mut_copy("ccddee", s);
	assert(s.length == 7);
	assert(s[5] == 'e');
	assert(s[6] == 0);
}