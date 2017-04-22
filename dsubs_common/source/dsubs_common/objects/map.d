module dsubs_common.objects.map;

import gfm.math.box;

/// Game world map.
/// At first versions of dsubs it's a simple rectangle. No internal topology.
/// Physical objects passing through edges will be pushed back.
class Map
{
    box2d bounds;
}
