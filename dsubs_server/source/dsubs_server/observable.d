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

module dsubs_server.observable;

import dsubs_common.api.entities;
public import dsubs_common.api.deventities;
import dsubs_common.json;

import dsubs_server.common;


struct StructuredObservableEntityUpdate
{
	string id;
	string entityType;
	KinematicSnapshot transformSnapshot;
	JSONValue stateUpdateJson;

	ObservableEntityUpdate toUnstructured()
	{
		return ObservableEntityUpdate(
			this.id, this.entityType, this.transformSnapshot,
			stateUpdateJson.toString());
	}
}


struct ObservableEntityCache
{
	bool generated;
	StructuredObservableEntityUpdate entityUpdateCache;
	SimulatorLogRecord[] logRecords;

	void clearCache()
	{
		generated = false;
		JSONValue[string] objectFields;
		entityUpdateCache.stateUpdateJson = JSONValue(objectFields);	// empty object
		entityUpdateCache.entityType = null;
		entityUpdateCache.id = null;
		logRecords.length = 0;
	}

	alias entityUpdateCache this;

	void log(string entityId, string entityType, string message)
	{
		logRecords ~= SimulatorLogRecord(entityType, entityId, message);
	}
}


interface IObservableEntity
{
	/// Clear all internal caches at the start of the simulation cycle.
	void markNewObservationEpoch();

	/// Generate entity update record to send to the observer. Should be cached
	/// and returns the same result after the markNewObservationEpoch call.
	StructuredObservableEntityUpdate getObserverUpdate();

	/// If the component desires to notify observers about some updates
	/// that happend during the last simulation cycle, it will append
	/// the records to 'appendTo' slice and return the number of records
	/// appended.
	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo);
}


interface IObservableCollection
{
	/// Clear all internal caches at the start of the simulation cycle.
	void markNewObservationEpoch();

	// both return the number of elements appended
	size_t appendObserverEntityUpdates(ref ObservableEntityUpdate[] appendTo);
	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo);
}


private string baseName(ClassInfo classinfo)
{
	import std.array;
	import std.algorithm : countUntil;
	import std.range : retro;

	string qualName = classinfo.name;

	ptrdiff_t dotIndex = qualName.retro.countUntil('.');

	if (dotIndex < 0) {
		return qualName;
	}

	return qualName[$ - dotIndex .. $];
}


string classBaseName(Object instance)
{
	if (instance is null) {
		return "null";
	}

	return instance.classinfo.baseName;
}