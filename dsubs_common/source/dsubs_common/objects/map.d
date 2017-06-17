module dsubs_common.objects.map;

/// Game world map.
/// At first versions of dsubs it's a simple rectangle. No internal topology.
/// Physical objects passing through edges will be pushed back.
struct Map
{
	double width;
	double height;
}
