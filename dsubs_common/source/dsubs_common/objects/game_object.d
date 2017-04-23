module dsubs_common.objects.game_object;

/// `exported` string attribute is used to mark all fields and properties that
/// can be remotely changed. For example, server periodically updates position
/// property of player's submarine.
/// `exported` can not be used on methods. Every action can be done via
/// property assignment anyways.

/// Any entity in game world can be represented this way.
class GameObject
{
	/// Global id of an object. Is the same for both client and server.
	/// Both server and client can update individual object states by
	/// referencing them directly by id. It's advantageous for nested
	/// object structures, because you don't need an URI for that case.
	///
	/// Object id is always assigned by the server.
	string id;
}
