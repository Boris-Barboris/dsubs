module dsubs_common.math.transform;

import std.container : DList;

import gfm.math.matrix;
import gfm.math.vector;


// Hierarchical transform
class Transform2D
{
    protected
    {
        mat3x3d local_transform;
        mat3x3d world_cache;  // cached value of world-coordinates transform
        Transform2D _parent;
    }

    DList!Transform2D children;

    /// Propagate parent's world transform to curren one
    protected void propagate()
    {
        // multiply parent's world_cache onto local_transform and save the
        // result as current transform world_cache. Then propagate changes
        // to all children
        world_cache =
        foreach (t; children)
            t.propagate();
    }

    @property Transform2D parent() { return _parent; }

    @property const mat3x3d local() { return local_transform; }
}
