// Spawning API

module dsubs_common.api.spawn;

import dsubs_common.api.constants;
import dsubs_common.api.utils;
import dsubs_common.objects.entities;
import dsubs_common.objects.map;

/// Send this unit in order to check whether you have a right to spawn, and,
/// if not, when will you have.
struct SpawnAvailiableReq
{
}

/// Server's response to spawn request.
struct SpawnAvailiableResp
{
	bool available;		// when true, you don't need to wait
	uint msecs_left;	// you need to wait that many milliseconds

	// if unavailiable, reason will be explained here in human-readable form
	@MaxLenAttr(128) string reason;
}

/// Client sends unit when requesting spawning.
struct SpawnRequest
{
	// sub loadout, chosen by the player
	ID_TYPE hull_id;
	ID_TYPE[] modules;
}

/// Right after authorization you recieve current map
struct MapInfoUnit
{
	USECS server_time;
	Map map;
}
