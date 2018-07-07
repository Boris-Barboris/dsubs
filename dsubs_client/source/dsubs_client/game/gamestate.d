module dsubs_client.game.gamestate;

import dsubs_client.game;


enum GameStateKind
{
	MAINMENU,
	LOADOUT,
	SIMULATION
}

abstract class GameState
{
	private GameStateKind m_kind;

	this(GameStateKind k) { m_kind = k; }

	/// type of this game state
	final @property GameStateKind kind() const { return m_kind; }

	/// Transform the Game into this state.
	/// Only called while holding Game.mainMutex.
	void setup();

	/// Called when backend connection is closed.
	void handleBackendDisconnect();

	/// Called when CIC connection is closed.
	void handleCICDisconnect();
}