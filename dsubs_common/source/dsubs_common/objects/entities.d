module dsubs_common.objects.entities;

import dsubs_common.api.constants;
import dsubs_common.objects.visual;


enum InfoSource: ubyte
{
	Player,     // object is player's avatar.
	Phantom,    // object is a phantom that does not correspond to real object's position,
				// but is broadcasted for player's convenience. For example,
				// first seconds of player's torpedo lives.
	TrueSight,  // accurate representation of an entity
}

// subs, torps, decoys, other stuff
struct Craft
{
	ID_TYPE id;
	ID_TYPE hull_id;	// hull type identifier
	InfoSource source;	// how does the player know about it?
	bool alive;			// known only for Player and TrueSight ships
}

struct ShipHull
{
	ID_TYPE id;		// unique hull identifier
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
	ID_TYPE[] module_choice;		// ids of module classes to choose from
	bool visible;		// does module have a model?
	vec2f position;		// if yes, model parameters
	float rotation;
	float scale;
	bool mirrored;
}

enum ModuleType: ubyte
{
	HullStructure,
	HullShell,
	HullCovering,
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

struct ShipModuleClass
{
	ID_TYPE id;
	ModuleType type;
	string name;
	string description;
}

enum ModuleHealth: ubyte
{
	OK,
	RECOVERABLE,
	BROKEN,
}

enum PropellerType: ubyte
{
	Screw,
	FixedModel
}

struct PropellerModel
{
	ID_TYPE id;
	PropellerType type;
	ubyte blade_count;		// for screws
	Contour contour;
}

struct PropulsorModule
{
	static ModuleType type = ModuleType.Propulsor;
	ID_TYPE id;
	ID_TYPE class_id;
	ID_TYPE model_id;		// id of PropellerModel
	bool enabled;
	ModuleHealth health;
	// two following values are not guaranteed to match server model:
	float max_rpm;			// on 1.0 or -1.0 throttle this will be the rpm
	float acc_spd;			// normalized acceleration speed
}
