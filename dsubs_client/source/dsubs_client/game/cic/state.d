module dsubs_client.game.cic.state;

import dsubs_common.api.protocols.backend;


/**
In-memory database for CIC server. CICState is born when the client spawns in
game world and is destroyed only on the next spawn or when the process dies.
Important data is periodically dumped to disk in order to be able to survive
CIC server crash.
*/
final class CICState
{
}