// Spawning API

module dsubs_common.api.spawn;

import dsubs_common.api.utils;
import dsubs_common.objects.map;

/// Send this unit in order to check whetherr you have a right to spawn, and
/// if now, when will you have.
struct SpawnAvailiableReq
{
}

/// Server's response.
struct SpawnAvailiableResp
{
	bool availiable;    // when true, you don't need to wait
	uint msecs_left;    // you need to wait that many milliseconds
	// if unavailiable, reason will be explained here in human-readable form
	@MaxLenAttr(128) string reason;
}

/// Client sends unit when requesting spawning.
/// Future versions will have loadouts, some kind of currency etc, the loadout
/// will be passed by this request.
struct SpawnRequest
{
}

enum SpawnStatus: ubyte
{
	OK = 0,
	UNAVAILIABLE = 1
	// some kind of `wrong_loadout` will be here too
}

/// Server responds to SpawnRequest with this unit. It contains world time
/// information, map parameters.
/// Player's ship will then be passed to client under standard `object`
/// synchronization API.
struct SpawnResponse
{
	SpawnStatus status;
	ulong usecs;		// game world absolute time in microseconds

	// server passes the map if the status is OK
	// if map will become more complex later on, it will need it's own
	// unit.
	box2d map_borders;

	Map initialize_map()
	{
		return new Map(map_borders);
	}

	bool spawned() { return status == SpawnStatus.OK; }
}
