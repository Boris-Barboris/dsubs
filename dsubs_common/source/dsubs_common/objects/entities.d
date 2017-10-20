module dsubs_common.objects.entities;

import dsubs_common.api.constants;
import dsubs_common.api.utils;
import dsubs_common.objects.visual;


enum InfoSource: ubyte
{
	Player,     // object is player's avatar.
	Phantom,    // object is a phantom that does not correspond to real object's position,
				// but is broadcasted for player's convenience. For example,
				// first seconds of player's torpedo life.
	TrueSight,  // accurate representation of an entity
}

enum ModuleHealth: ubyte
{
	OK,
	LightDamage,
	HeavyDamage,
	Lost,
}

// subs, torps, decoys, other stuff
struct Craft
{
	ID_TYPE id;
	ID_TYPE hull_id;	// hull type identifier
	InfoSource source;	// how does the player know about it?
	bool alive;			// known only for Player and TrueSight ships
	ID_TYPE[] modules;	// modules that are fitted on the craft
}

struct ShipHull
{
	ID_TYPE id;
	string name;
	string description;
	VisualModel model;
	MountPoint[] mounts;	// player customizes his sub using modules
	bool controllable;
}

struct MountPoint
{
	ID_TYPE id;
	string name;
	ID_TYPE[] module_choice;	// ids of module descriptors to choose from
	bool visible;				// does module have a model?
	Vector2!float position;		// if yes, model parameters
	float rotation;
	Vector2!float scale;
}

enum ModuleType: ubyte
{
	HullMod,
	PowerPlant,
	PowerStorage,
	Propulsor,
	PassiveSonar,
	ActiveSonar,
	ActiveInterceptor,
	Silo,
	WeaponRack,
	PassiveJammer,
	DirectedJammer,
	TowedModuleMount,

	ModuleTypeCount,
}

struct ShipModuleDescriptor
{
	ID_TYPE id;
	ModuleType type;
	string name;
	string description;
}

enum PropellerType: ubyte
{
	Screw,		// rotating blades
	FixedModel,	// no animation, pump jet or similar
}

struct PropellerModel
{
	ID_TYPE id;
	PropellerType type;
	ubyte blade_count;		// for screws, zero for pumps
	Contour contour;		// one blade or whole pump contour
}

struct PropulsorModule
{
	alias type = ModuleType.Propulsor;
	ID_TYPE id;
	ID_TYPE desc_id;		// descriptor id
	ID_TYPE model_id;		// id of PropellerModel
	// two following values are not guaranteed to match server model:
	float max_angvel;		// on 1.0 or -1.0 throttle will rotate blades with
							// this angular velocity
	float ang_acc;			// angular acceleration
}
