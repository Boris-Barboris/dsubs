module dsubs_common.objects.physical;

public import dsubs_common.api.constants;
public import dsubs_common.api.utils;

/// Structure that represents snapshot of kinematic parameters of one particular
/// physical object. Sent by server to update client with positions of real
/// objects known to him.
struct PhysicalSnapshot
{
	ID_TYPE id;             // id of the object (Craft)
	USECS time;
	Vector2!double position;
	Vector2!double velocity;
	double ang_vel;
	double rotation;
}
