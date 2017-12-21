module dsubs_common.math.hash;

/// http://www.cse.yorku.ca/~oz/hash.html
pure ulong djb2(string str) @safe
{
    ulong hash = 5381;
    foreach (char c; str)
        hash = ((hash << 5) + hash) + c;
    return hash;
}
