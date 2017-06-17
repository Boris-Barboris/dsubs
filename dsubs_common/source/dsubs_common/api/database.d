// API reference for entity database

module dsubs_common.api.database;

import dsubs_common.api.utils;
import dsubs_common.objects;


alias DbVersionType = uint;


/// Bit unit, sent by the server after authorization and synchronizes client's
/// database with the server.
struct EntityDatabase
{
	DbVersionType db_version;
	ShipHull[] hulls;
	ShipModuleDescriptor[] moduleDescriptors;
	PropellerModel[] prop_models;
	PropulsorModule[] propulsors;
}

/// Sent by client to query server database version.
/// The same unit is sent in response.
mixin SingleValueUnit!("DatabaseVersion", DbVersionType, "db_version");
