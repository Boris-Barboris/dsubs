module dsubs_client.game.cic.state;

import dsubs_common.api.protocols.backend;


/**
In-memory database for state that is replicated between backend and CIC,
and between all the clients. CICState is born when the client spawns in
game world and is destroyed only on the next spawn or when the process dies.
Client-only data is periodically dumped to disk in order to be able to survive
master client crash.
*/
final class CICState
{
	private
	{
		EntityDbRes m_entityDb;
		ReconnectStateRes
	}
}