module dsubs_server.sensors;

import dsubs_common.api.messages;

import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.dynamics;


struct SubHydrophonePrototype
{
	string name;
	HydrophoneType type;
	MountPoint mount;
	HydrophonePrototype hydroProto;
	/// wire parameters for towed array.
	AttachedWirePrototype wirePrototype;

	@property HydrophoneTemplate getTemplate()
	{
		return HydrophoneTemplate(
			name, type, mount, hydroProto.antennaeSpan, hydroProto.antennaeRots, wirePrototype.maxLength);
	}
}