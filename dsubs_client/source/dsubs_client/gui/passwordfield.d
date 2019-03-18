module dsubs_client.gui.passwordfield;

import std.array: array;
import std.range: repeat, take;

import derelict.sfml2.graphics;

public import dsubs_common.mutstring;

import dsubs_client.gui.textfield;


final class PasswordField: TextField
{
	enum dchar PWDOT = '•';

	/// actual password will be here
	private dmutstring m_hiddenContent;

	this()
	{
		m_hiddenContent = _s(""d, 31);
	}

	alias content = typeof(super).content;

	@property override dmutstring content() { return m_hiddenContent; }

	@property override void content(dstring rhs)
	{
		str2mutCopy(rhs, m_hiddenContent);
		m_content.length = m_hiddenContent.length;
		m_content[0 .. $-1] = PWDOT;
		m_content[$-1] = 0;
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	override void insertAt(dchar c, size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.insertAt(c, idx);
		m_content.insertAt(PWDOT, idx);
	}

	override void insertAt(dstring s, size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.insertAt(s, idx);
		m_content.insertAt(repeat(PWDOT).take(s.length).array, idx);
	}

	override void removeAt(size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.removeAt(idx);
		m_content.removeAt(idx);
	}

	override void removeInterval(size_t start, size_t end)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.removeInterval(start, end);
		m_content.removeInterval(start, end);
	}
}
