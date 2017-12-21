module dsubs_common.mutstring;

import std.algorithm.comparison;
import std.string;


/** Alias for simple mutable string, that we all need so much
in gaming in order to prevent excessive reallocations.
Mutstrings are null-terminated, since they are needed for
external libraries written in C. */
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

/// Creates mutstring from string, reserving space for at least size
/// meaningful symbols
CharT[] _s(CharT)(immutable(CharT)[] s, size_t size) nothrow pure @safe
{
	size_t len = max(s.length, size);
	CharT[] res;
	res.reserve(len + 1);
	res.length = s.length + 1;
	for (size_t i = 0; i < s.length; i++)
		res[i] = s[i];
	res[s.length] = 0;
	return res;
}

/// Copy string contents into mutstring, extending it if
/// required.
void str2mutCopy(CharT)(immutable(CharT)[] s, ref CharT[] ms) nothrow @safe
{
	ms.length = s.length + 1;
	for (size_t i = 0; i < s.length; i++)
		ms[i] = s[i];
	ms[s.length] = 0;
}

/// Replace symbols from index start to end in string s with one character c
/// String never increases it's size.
/// end is inclusive
void replaceInterval(CharT)(ref CharT[] s, size_t start, size_t end, CharT c)
{
	s[start] = c;
	size_t shift = end - start;
	if (shift > 0)
	{
		for (size_t i = start + 1; i < s.length - shift; i++)
			s[i] = s[i+shift];
		s.length = s.length - shift;
	}
}

unittest
{
	mutstring s = _s("as");
	s.replaceInterval(0, 1, 'd');
	assert(equal(s[0..1], "d"));
}

/// end is inclusive
void removeInterval(CharT)(ref CharT[] s, size_t start, size_t end)
{
	size_t shift = end - start + 1;
	if (shift > 0)
	{
		for (size_t i = start; i < s.length - shift; i++)
			s[i] = s[i+shift];
		s.length = s.length - shift;
	}
}

unittest
{
	mutstring s = _s("asdf");
	s.removeInterval(1, 2);
	assert(equal(s[0..2], "af"));
}

void insertAt(CharT)(ref CharT[] s, CharT c, size_t at)
{
	++s.length;
	for (size_t i = s.length - 1; i > at; i--)
		s[i] = s[i - 1];
	s[at] = c;
}

unittest
{
	mutstring s = _s("as");
	s.insertAt('d', 0);
	s.insertAt('d', 0);
	assert(equal(s[0..4], "ddas"));
}

void removeAt(CharT)(ref CharT[] s, size_t at)
{
	if (at < s.length - 1 && at >= 0)
	{
		for (size_t i = at; i < s.length - 1; i++)
			s[i] = s[i + 1];
		--s.length;
	}
	else
		throw new Exception("Out of mutstring content bounds");
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
	assert(s.length == 7);
	assert(s.capacity >= 20 - 6);
}

nothrow unittest
{
	mutstring s = _s("aabb");
	str2mutCopy("ccddee", s);
	assert(s.length == 7);
	assert(s[5] == 'e');
	assert(s[6] == 0);
}
