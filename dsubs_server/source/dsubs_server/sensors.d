module dsubs_server.sensors;

import dsubs_common.api.messages;

import dsubs_sound.hydrophone;
import dsubs_sound.activesonar;

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

	@property const(HydrophoneTemplate) tmpl() const
	{
		return HydrophoneTemplate(
			name, type, mount, hydroProto.antennaeSpan, hydroProto.antennaeRots, wirePrototype.maxLength);
	}
}


struct SubSonarPrototype
{
	MountPoint mount;
	ActiveSonarPrototype sonarProto;

	@property const(SonarTemplate) tmpl() const
	{
		return SonarTemplate(
			mount, sonarProto.span.dgr2rad, sonarProto.maxPeakIlevel,
			sonarProto.minPeakIlevel, sonarProto.getSliceXResol(), sonarProto.radialRes,
			sonarProto.maxSec);
	}
}