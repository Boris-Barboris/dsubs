module dsubs_server.db.account;

import std.conv: to;
import std.digest.sha;
import std.format: format;

import dsubs_server.exceptions;

class Account
{
	string id;
	string email;

	@property string password() { return _password; }
	@property string password(string pw) 
	{
		_passwordHash = Account.password_sha(pw);
		return _password = pw;
	}	
	@property immutable(ubyte)[] passwordHash() { return _passwordHash; }	

	private
	{
		string _password;
		immutable(ubyte)[] _passwordHash;
	}

	// In-memory constructor
	this(string id, string password, string email)
	{
		this.id = id;
		this.email = email;
		this.password = password;
	}

	// Constructor to build from database data, wich doesn't store passwords
	this (string id, string email, immutable(ubyte)[] pwhash)
	{
		this.id = id;
		this.email = email;
		this._passwordHash = pwhash;
	}

	static immutable(ubyte)[] password_sha(string password)
	{
		return to!(immutable(ubyte)[])(sha256Of(password));
	}

	bool authorized(Account other)
	{
		return (id == other.id &&
				passwordHash == other.passwordHash);
	}
}

unittest
{
	import std.stdio;
	Account acc1 = new Account("id1", "password", "email");
	Account acc2 = new Account("id2", "password", "email");
	assert(acc1.passwordHash == acc2.passwordHash);
	writeln(toHexString(acc1.passwordHash));
}


/// Controller to handle Account CRUD
class AccountManager
{
	/// Return account information by id.
	/// Null if no such account found.
	abstract Account get(string id);

	/// Return true if this account is authorized
	bool authorize(Account acc)
	{
		Account existing = get(acc.id);
		if (existing is null)
			return false;
		return existing.authorized(acc);
	}

	/// Register an account. If something goes wrong, exception will be
	/// thrown.
	void register(Account acc)
	{
		if (get(acc.id))
			throw new AlreadyExists(
				format("Account with id %s already exists", acc.id));
		put(acc);
	}

	protected abstract void put(Account acc);

	abstract bool remove(Account acc);
}


/// In-memory testing manager with admin account created
package class AccountManagerRam: AccountManager
{
	Account[string] map;

	this()
	{
		map["admin"] = new Account("admin", "admin", "adminemail");
	}

	override Account get(string id)
	{
		return map.get(id, null);
	}

	override protected void put(Account acc)
	{
		map[acc.id] = acc;
	}

	override bool remove(Account acc)
	{
		if (acc.id in map)
		{
			map.remove(acc.id);
			return true;
		}
		else
			return false;
	}
}

unittest
{
	auto manager = new AccountManagerRam();
	auto acc = new Account("testacc", "testpw", "testemail");
	manager.register(acc);
	auto output = manager.get("testacc");
	assert(output is acc);
	auto testacc = new Account("testacc", "testpw", "testmail2");
	assert(manager.authorize(testacc));

	import std.exception;
	assertThrown!(AlreadyExists)(
		manager.register(new Account("testacc", "testpw", "")));
	assert(manager.remove(new Account("testacc", "", "")));
}