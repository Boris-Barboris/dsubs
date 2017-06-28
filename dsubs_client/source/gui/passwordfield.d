module dsubs_client.gui.passwordfield;

import derelict.sfml2.graphics;

public import dsubs_common.mutstring;

import dsubs_client.gui.textfield;
import dsubs_client.gui.manager;


class PasswordField: TextField
{
	static immutable dchar PWDOT = '•';

	protected
	{
		dmutstring _hidden_content;     // actual password will be here
	}

	this(GuiManager manager)
	{
		_hidden_content = _s(""d, 63);
		super(manager);
	}

	invariant
	{
		assert(_hidden_content.length == _content.length);
	}

	override const(dmutstring) content() { return _hidden_content; }

	override PasswordField content(dstring val)
	{
		str2mut_copy(val, _hidden_content);
		_content.length = _hidden_content.length;
		_content[0 .. $-1] = PWDOT;
		_content[$-1] = 0;
		sfText_setUnicodeString(text, _content.ptr);
		_visuals_dirty = true;
		return this;
	}

	override void insert_at(dchar c, size_t idx)
	{
		_hidden_content.insert_at(c, idx);
		_content.insert_at(PWDOT, idx);
	}

	override void remove_at(size_t idx)
	{
		_hidden_content.remove_at(idx);
		_content.remove_at(idx);
	}

	override void remove_interval(size_t start, size_t end)
	{
		_hidden_content.remove_interval(start, end);
		_content.remove_interval(start, end);
	}
}

PasswordField asPasswordField(GuiElement el)
{
	return cast(PasswordField) el;
}
