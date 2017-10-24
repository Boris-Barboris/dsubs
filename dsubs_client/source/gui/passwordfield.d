module dsubs_client.gui.passwordfield;

import derelict.sfml2.graphics;

public import dsubs_common.mutstring;

import dsubs_client.gui.textfield;


final class PasswordField: TextField
{
	static immutable dchar PWDOT = '•';

	private
	{
		dmutstring _hidden_content;     // actual password will be here
	}

	this()
	{
		super();
		_hidden_content = _s(""d, 31);
	}

	@property override const(dmutstring) content() const { return _hidden_content; }

	override PasswordField content(dstring val)
	out (result)
	{
		assert(_hidden_content.length == _content.length);
	}
	body
	{
		str2mut_copy(val, _hidden_content);
		_content.length = _hidden_content.length;
		_content[0 .. $-1] = PWDOT;
		_content[$-1] = 0;
		sfText_setUnicodeString(text, _content.ptr);
		update_text();
		return this;
	}

	override void insert_at(dchar c, size_t idx)
	out
	{
		assert(_hidden_content.length == _content.length);
	}
	body
	{
		_hidden_content.insert_at(c, idx);
		_content.insert_at(PWDOT, idx);
	}

	override void remove_at(size_t idx)
	out
	{
		assert(_hidden_content.length == _content.length);
	}
	body
	{
		_hidden_content.remove_at(idx);
		_content.remove_at(idx);
	}

	override void remove_interval(size_t start, size_t end)
	out
	{
		assert(_hidden_content.length == _content.length);
	}
	body
	{
		_hidden_content.remove_interval(start, end);
		_content.remove_interval(start, end);
	}
}

PasswordField asPasswordField(GuiElement el)
{
	return cast(PasswordField) el;
}
