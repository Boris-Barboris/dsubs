module dsubs_common.mutstring;

import std.algorithm.comparison;
import std.string;

/// Alias for simple mutable ASCII string, that we all need so much
/// in gaming in order to prevent excessive allocations.
alias mutstring = char[];
alias dmutstring = dchar[];		// 32-bit unicode

/// Creates mutstring from string
CharT[] _s(CharT)(immutable(CharT)[] s) nothrow pure @safe
{
	size_t len = s.length;
	CharT[] res = new CharT[len + 1];
	for (size_t i = 0; i < len; i++)
		res[i] = s[i];
	res[len] = 0;
	return res;
}

/// Creates mutstring from string, allocating space for at least size symbols
CharT[] _s(CharT)(immutable(CharT)[] s, size_t size) nothrow pure @safe
{
	size_t len = max(s.length, size);
	CharT[] res = new CharT[len + 1];
	for (size_t i = 0; i < s.length; i++)
		res[i] = s[i];
	res[s.length] = 0;
	return res;
}

/// Copy string contents into mutstring, extending it if
/// required.
void str2mut_copy(CharT)(immutable(CharT)[] s, CharT[] ms) nothrow @safe
{
	if (s.length > ms.length - 1)
		ms.length = s.length + 1;
	for (size_t i = 0; i < s.length; i++)
		ms[i] = s[i];
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
	auto s = _s("юникод"d);
	static assert(is(typeof(s) == dmutstring));
	assert(equal(s[0..1], "ю"d));
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
