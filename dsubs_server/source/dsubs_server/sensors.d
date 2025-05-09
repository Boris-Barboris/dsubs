/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
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