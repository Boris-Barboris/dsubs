module dsubs_server.sensors;

import std.typecons: Nullable;

import dsubs_common.api.messages;
import dsubs_common.math.angles;

import dsubs_sound.hydrophone;
import dsubs_sound.activesonar;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.vessel: MountPointConfig;


struct SubHydrophonePrototype
{
	string name;
	HydrophoneType type;
	MountPointConfig mount;
	HydrophonePrototype hydroProto;
	/// wire parameters for towed array.
	Nullable!AttachedWirePrototype wirePrototype;

	@property const(HydrophoneTemplate) tmpl() const
	{
		return const HydrophoneTemplate(
			name, type, mount, hydroProto.antennaeSpan, hydroProto.antennaeRots,
			wirePrototype.isNull ? 0.0f : wirePrototype.get.maxLength);
	}
}


struct SubSonarPrototype
{
	MountPointConfig mount;
	ActiveSonarPrototype sonarProto;

	@property const(SonarTemplate) tmpl() const
	{
		return const SonarTemplate(
			mount, sonarProto.span.dgr2rad, sonarProto.maxPeakIlevel,
			sonarProto.minPeakIlevel, sonarProto.getSliceXResol(), sonarProto.radialRes,
			sonarProto.maxSec);
	}
}