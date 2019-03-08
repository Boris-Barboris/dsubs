/**
Functions for mutable char[] and dchar[] operations.
*/

module dsubs_common.mutstring;

import std.algorithm.comparison;
import std.string;
import std.utf;
import std.format;
import std.traits: isSomeChar;


alias mutstring = char[];
alias dmutstring = dchar[];


@safe:

/// Create mutstring from string with the same code unit size.
CharT[] _s(CharT)(immutable(CharT)[] s) nothrow
	if (isSomeChar!CharT)
{
	size_t len = s.length;
	CharT[] res = new CharT[len + 1];
	for (size_t i = 0; i < len; i++)
		res[i] = s[i];
	res[len] = 0;
	return res;
}

/// Create mutstring from string, reserving space for at least 'size' code units.
CharT[] _s(CharT)(immutable(CharT)[] s, size_t size) nothrow
	if (isSomeChar!CharT)
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

/// Copy string contents into mutstring, extending it if required.
void str2mutCopy(CharT)(immutable(CharT)[] from, ref CharT[] to) nothrow
	if (isSomeChar!CharT)
{
	to.length = from.length + 1;
	for (size_t i = 0; i < from.length; i++)
		to[i] = from[i];
	to[from.length] = 0;
}

/// ditto
void str2mutCopy(CharT)(const CharT[] from, ref CharT[] to) nothrow
	if (isSomeChar!CharT)
{
	to.length = from.length + 1;
	for (size_t i = 0; i < from.length; i++)
		to[i] = from[i];
	to[from.length] = 0;
}

/// ditto
void str2mutCopy(CharT1, CharT2)(const CharT1[] from, ref CharT2[] to)
	if (isSomeChar!CharT1 && isSomeChar!CharT2 && !is(CharT1 == CharT2))
{
	to.reserve(from.length + 1);	// rough heuristic
	to.length = 0;
	foreach (symb; from.byUTF!CharT2)
		to ~= symb;
	to ~= cast(CharT2) 0;
}

/// ditto
void str2mutCopy(CharT1, CharT2)(immutable(CharT1)[] from, ref CharT2[] to)
	if (isSomeChar!CharT1 && isSomeChar!CharT2 && !is(CharT1 == CharT2))
{
	to.reserve(from.length + 1);	// rough heuristic
	to.length = 0;
	foreach (symb; from.byUTF!CharT2)
		to ~= symb;
	to ~= cast(CharT2) 0;
}

unittest
{
	mutstring s = _s("aabb");
	str2mutCopy("ccddee", s);
	assert(s.length == 7);
	assert(s[5] == 'e');
	assert(s[6] == 0);
}

/// Write 'args' formatted by format string 'fmt' to dmutstring 'dest'.
void mutsformat(string fmt, Args...)(ref dmutstring dest, Args args)
{
	static char[128] tmpbuf = 0;	// yes, I know...
	char[] res = sformat!(fmt)(tmpbuf[], args);
	str2mutCopy(res, dest);
}

/// Copy mutstring to new string.
string str(const dmutstring mut)
{
	return mut[0..$-1].toUTF8;
}

/// ditto
string str(const mutstring mut)
{
	return mut[0..$-1].toUTF8;
}

/// Remove dmutstring elements starting at index 'start' and including
/// 'end' index.
void removeInterval(ref dmutstring s, size_t start, size_t end)
{
	assert(end >= start);
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
	dmutstring s = _s("asdf"d);
	assert(s.length == 5);
	s.removeInterval(1, 2);
	assert(s.length == 3);
	assert(equal(s[0..2], "af"));
}

/// Insert char 'c' at index 'at' into dmustring.
void insertAt(CharT)(ref dmutstring s, CharT c, size_t at)
	if (isSomeChar!CharT)
{
	assert(at < s.length);
	++s.length;
	for (size_t i = s.length - 1; i > at; i--)
		s[i] = s[i - 1];
	s[at] = c;
}

/// Insert char 'c' at index 'at' into dmustring.
void insertAt(ref dmutstring s, dstring s2, size_t at)
{
	assert(at < s.length);
	if (s2.length == 0)
		return;
	s.length += s2.length;
	for (size_t i = s.length - 1; i >= at + s2.length; i--)
		s[i] = s[i - s2.length];
	s[at .. at + s2.length] = s2[];
}

unittest
{
	dmutstring s = _s("as"d);
	s.insertAt('d', 0);
	s.insertAt('d', 0);
	assert(equal(s[0..4], "ddas"));
}

/// Remove character at index 'at' from dmustring.
void removeAt(ref dmutstring s, size_t at)
{
	assert(s.length > 0);
	assert(at < s.length);
	for (size_t i = at; i < s.length - 1; i++)
		s[i] = s[i + 1];
	--s.length;
}

unittest
{
	dmutstring s = _s("asdf"d);
	s.removeAt(2);
	assert(equal(s[0..$-1], "asf"d));
	s.removeAt(0);
	assert(equal(s[0..$-1], "sf"d));
}

unittest
{
	mutstring s = _s("asdf");
	assert(s[0] == 'a');
	assert(s[3] == 'f');
	assert(s[4] == 0);
	assert(indexOf(s, 'd') == 2);
	assert(indexOf(s, 'x') == -1);
}

unittest
{
	auto s = _s("юникод"d);
	static assert(is(typeof(s) == dmutstring));
	assert(equal(s[0..1], "ю"d));
}

unittest
{
	mutstring s = _s("foobar", 20);
	assert(s.length == 7);
	assert(s.capacity >= 20 - 6);
}


/// OutputRange implementation that rewrites the mutstring content.
/// Usefull in pair with std.formattedwrite.
auto mutstringRewriter(Char)(Char[] base)
	if (isSomeChar!Char)
{
	static struct Writer
	{
		Char[] base;
		size_t len = 0;
		void put(Char c)
		{
			if (len == base.length - 1)
				base.length += 8;
			base[len++] = c;
		}
		Char[] get()
		{
			base.length = len + 1;
			base[len] = 0;
			return base;
		}
	}

	return Writer(base);
}

unittest
{
	import std.format;

	mutstring s = _s("123");
	auto rw = mutstringRewriter(s);
	formattedWrite(rw, "%d", 77);
	s = rw.get();
	assert(s.length == 3);
	assert(s[2] == 0);
	assert(s[0..2] == "77");
}