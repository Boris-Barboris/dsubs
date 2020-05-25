module dsubs_client.game.gamestate;

import dsubs_common.api.messages;
import dsubs_client.game;


abstract class GameState
{
	/// Transform the Game into this state.
	/// Only called while holding Game.mainMutex.
	void setup();

	/// Called when backend connection is closed.
	void handleBackendDisconnect();

	/// Called when CIC connection is closed.
	void handleCICDisconnect();

	/// Called when backend connection receives SimulatorTerminatingRes
	void handleSimulatorTerminatingRes()
	{
		throw new Exception("Unexpected SimulatorTerminatingRes");
	}

	/// Called in multiple stages, right after successfull login and after
	void handleAvailableScenariosRes(AvailableScenariosRes res)
	{
		throw new Exception("Unexpected AvailableScenariosRes");
	}
}