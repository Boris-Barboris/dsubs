module dsubs_common.objects.intelligence;


enum InfoSource: ubyte
{
    Player,     // object is player's avater.
    Phantom,    // object is a phantom that does not correspond to real object's position,
                // but is broadcasted for player's convenience. For example,
                // first seconds of player's torpedos lives.
    TrueSight,  // accurate representation of an entity
}
