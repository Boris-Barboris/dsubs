module dsubs_common.objects.physical;

public import gfm.math.vector;

public import dsubs_common.api.constants;

/// Structure that represents snapshot of kinematic parameters of one particular
/// physical object. Sent by server to update client with positions of real
/// objects known to him.
struct PhysicalSnapshot
{
	ID_TYPE id;             // id of the object
	vec2d position;
	vec2d velocity;
	double ang_vel;
	double rotation;
}
