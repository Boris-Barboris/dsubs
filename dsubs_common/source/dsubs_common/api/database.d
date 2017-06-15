// API reference for entity database

module dsubs_common.api.database;

import dsubs_common.api.utils;
import dsubs_common.objects;


/// Unit is sent by the server after authorization and gives the client
/// accepted hulls.
struct EntityDatabase
{
	ShipHull[] hulls;
	ShipModuleClass[] moduleClasses;
	PropellerModel[] prop_models;
	PropulsorModule[] propulsors;
}
