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
}

struct MountPoint
{
	ID_TYPE id;
	string name;
	vec2f position;
	float rotation;
	bool mirrored;
	bool visible;		// does module have a model?
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

	ModuleTypeCount,
}

struct ShipModuleClass
{
	ID_TYPE id;
	ModuleType type;
	string name;
	string description;
}
