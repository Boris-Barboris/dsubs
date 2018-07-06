module dsubs_client.game.cic.server;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.cic.listener;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.state;

public import dsubs_client.game.connections.cicclient;


/**
CIC stands for command information center. It is a broadcast server responsible
for cooperative gameplay.
*/
final class CICServer
{
	private
	{
		CICListener m_listener;
	}

	mixin Readonly!(int, "spawnId");

	this(string password, int spawnId = -1)
	{
		m_listener = new CICListener(this, password);
		m_spawnId = spawnId;
	}

	void start()
	{
		m_listener.start();
	}

	void stop()
	{
		m_listener.stop();
	}

	void handleSubKinematicRes(SubKinematicRes res)
	{
		m_listener.broadcast(res);
	}
}