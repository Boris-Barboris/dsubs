// API reference for entity state updates

module dsubs_common.api.state;

import dsubs_common.api.constants;
import dsubs_common.api.utils;
import dsubs_common.objects;


/// This unit is periodically sent by client (lone unit) and will
/// instantly be echoed back. Used for ping estimation.
mixin SingleValueUnit!("TimeSync", ID_TYPE, "sync_id");

/// Sent by the server to let the client know about the craft.
/// Used at least once to show player's craft to the client.
mixin IdAndValueUnit!("CraftInfo", Craft, "craft");

/// Sent by the server to update client on some module's health
mixin IdAndValueUnit!("HealthUpdate", ModuleHealth, "new_health");

/// Sent by the server to publish craft position
mixin IdAndValueUnit!("KinematicsUpdate", PhysicalSnapshot, "snapshot");

/// Server kills the player with this
struct PlayerKilled
{
	uint respawn_cooldown;
	@MaxLenAttr(256) string cause;	// what killed you
	@MaxLenAttr(256) string stats;	// some fancy statistics
}
