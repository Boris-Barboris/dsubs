module dsubs_common.objects.ship;

public import dsubs_common.api.constants;
public import dsubs_common.objects.intelligence;


struct Ship
{
	ID_TYPE id;
	uint hull_id;		// hull identifier
	InfoSource source;	// how does the player know about it?
}


/// Represents hull type
struct ShipHull
{
	uint hull_id;		// unique hull identifier
	string name;
	string description;
	// maybe price here
}
