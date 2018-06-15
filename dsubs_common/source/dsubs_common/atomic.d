module dsubs_common.atomic;

import core.atomic;


/// cas for non-shared class references, hack around D shared qualifier
bool pcas(T, V1, V2)(T* ptr, V1 ifThis, V2 putThis)
	if (is(T == class))
{
	return cas!(size_t, void*, size_t)(
		cast(shared size_t*) ptr, cast(const void*) ifThis, cast(size_t) putThis);
}