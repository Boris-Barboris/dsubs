
module dsubs_common.api.utils;

import dsubs_common.reflection;

immutable uint HEADER_SIZE = 8;
alias header_t = immutable(ubyte[HEADER_SIZE]);

mixin template DefaultDemarshaller(T)
{
	static T* demarshal(ubyte[] data, out uint shift)
	{
		shift = T.sizeof;
		return cast(T*) data.ptr;
		pragma(msg, "Default demarshalling for ", T, " size=", T.sizeof);
	}
}

mixin template DefaultMarshaller(T)
{
	uint marshal(ubyte[] stream)
	{
		uint shift = HEADER_SIZE + T.sizeof;
		for (uint i = 0; i < HEADER_SIZE; i++)
			stream[i] = T.header[i];
		stream = stream[HEADER_SIZE .. $];
		ubyte* struct_ptr = cast(ubyte*) &this;
		for (uint i = 0; i < T.sizeof; i++, struct_ptr++)
			stream[i] = *struct_ptr;
		return shift;
	}
}
