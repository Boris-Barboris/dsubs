module dsubs_client.game.gamestate;

import dsubs_client.game;


interface IGameState
{
	/// Transform the Game into this state.
	/// Only called while holding Game.mainMutex.
	void setup();

	/// Called when backend connection is closed.
	void handleBackendDisconnect();

	/// Called when CIC connection is closed.
	void handleCICDisconnect();
}