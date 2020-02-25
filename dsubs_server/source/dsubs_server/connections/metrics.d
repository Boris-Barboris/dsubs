module dsubs_server.connections.metrics;

import std.algorithm: map, merge;
import std.range: replace;
import std.base64: Base64;
import std.string: representation;
import std.array: Appender, appender;
import std.zlib;
import std.datetime;
import std.json;

import requests;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.animal;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.player;
import dsubs_server.torpedo: Weapon;
import dsubs_server.scenario;

import dsubs_common.proftimer;
import dsubs_common.api.messages;
import dsubs_common.api.entities;


final class MetricsService
{
	private string m_influxUrl;
	private string m_influxReadUrl;

	/// https://docs.influxdata.com/influxdb/v1.7/write_protocols/line_protocol_tutorial/#writing-data-to-influxdb
	/// influxUrl example: http://localhost:8086/write?db=science_is_cool
	this(string influxUrl)
	{
		m_influxUrl = influxUrl;
		m_influxReadUrl = influxUrl.replace("write", "query");
	}

	void writeMetrics(ProfTimer simTimer, int connectedPlayers)
	{
		try
		{
			auto strBuf = appender!string();
			// strBuf ~= "total_usecs=" ~ simTimer.getTotalUsecs.to!string;
			bool first = true;
			foreach (const ProfTimer.Interval interval; simTimer.readySubIntervals)
			{
				if (!first)
					strBuf ~= ",";
				strBuf ~= interval.name ~ "=" ~
					(interval.end - interval.start).total!"usecs".to!string;
				first = false;
			}
			postContent(m_influxUrl,
				"simulator_stats " ~ strBuf.data ~ "\n" ~
				"player_stats connected_players=" ~ connectedPlayers.to!string);
		}
		catch (Exception ex)
		{
			error("error writing metrics to influx: ", ex.msg);
		}
	}

	static string escape(string s)
	{
		return s.replace(" ", `\ `).replace(",", `\,`);
	}

	static string quote(string s)
	{
		return `"` ~ s ~ `"`;
	}

	void writeReplayData()
	{
		try
		{
			auto strBuf = appender!string();
			// write vessel states
			int counter = 0;
			synchronized(Globals.simMut.writer)
			{
				foreach (Vessel v; Globals.vessels.entities)
				{
					strBuf ~= "replay_data_vessels,simulator_instance=main_arena";
					strBuf ~= ",object_class_name=" ~ escape(typeid(v).name);
					// prototype name
					strBuf ~= ",prototype_name=" ~ escape(v.prototypeName);
					// pointer value
					strBuf ~= ",ptr=" ~ (cast (size_t) (cast (void*) v)).to!string;

					// alive/dead
					strBuf ~= " dead=" ~ v.dead.to!string;
					// captain name
					Submarine sub = cast(Submarine) v;
					Weapon wpn = cast(Weapon) v;
					if (sub && sub.captain)
						strBuf ~= ",captain_name=" ~ quote(Base64.encode(
							representation(sub.captain.name)));
					else if (wpn && wpn.shooterCaptain)
						strBuf ~= ",captain_name=" ~ quote(Base64.encode(
							representation(wpn.shooterCaptain.name)));
					else
						strBuf ~= ",captain_name=" ~ quote("__null__");
					// transform
					strBuf ~= ",pos_x=" ~ v.transform.wposition.x.to!string ~
						",pos_y=" ~ v.transform.wposition.y.to!string;
					// velocity
					strBuf ~= ",vel_x=" ~ v.rigidBody.kinet.vel.x.to!string ~
						",vel_y=" ~ v.rigidBody.kinet.vel.y.to!string;
					strBuf ~= "\n";
					counter++;
				}
				// write animals
				foreach (Animal a; Globals.animals.entities)
				{
					strBuf ~= "replay_data_animals,simulator_instance=main_arena";
					strBuf ~= ",object_class_name=" ~ escape(typeid(a).name);
					// prototype name
					strBuf ~= ",species=" ~ escape(a.species);
					// pointer value
					strBuf ~= ",ptr=" ~ (cast (size_t) (cast (void*) a)).to!string;

					// alive/dead
					strBuf ~= " dead=" ~ a.dead.to!string;
					// name
					strBuf ~= ",name=" ~ quote(a.name);
					// transform
					strBuf ~= ",pos_x=" ~ a.transform.wposition.x.to!string ~
						",pos_y=" ~ a.transform.wposition.y.to!string;
					// velocity
					strBuf ~= ",vel_x=" ~ a.rigidBody.kinet.vel.x.to!string ~
						",vel_y=" ~ a.rigidBody.kinet.vel.y.to!string;
					strBuf ~= "\n";
					counter++;
				}
			}
			if (counter)
			{
				// trace("posting: ", strBuf.data);
				auto res = postContent(m_influxUrl, strBuf.data[0..$-1],
					"application/binary");
				if (res.length)
					trace(res);
			}
		}
		catch (Exception ex)
		{
			error("error writing replay data to influx: ", ex.msg);
		}
	}

	private static ReplayObjectType classNameToROT(string name)
	{
		switch (name)
		{
			case "dsubs_server.submarine.Submarine":
				return ReplayObjectType.submarine;
			case "dsubs_server.torpedo.Torpedo":
				return ReplayObjectType.weapon;
			case "dsubs_server.torpedo.StaticDecoy":
				return ReplayObjectType.decoy;
			case "dsubs_server.animal.Animal":
				return ReplayObjectType.animal;
			default:
				return ReplayObjectType.unknown;
		}
	}

	ReplaySlice[] queryReplaySlices(
		string simulatorInstance, DateTime from, DateTime until)
	{
		enforce(simulatorInstance == "main_arena");
		string queryVessels = "SELECT time, " ~
			"object_class_name, dead, prototype_name, captain_name, " ~
			"pos_x, pos_y, vel_x, vel_y FROM replay_data_vessels WHERE " ~
			`simulator_instance = "` ~ simulatorInstance ~ `" AND ` ~
			`time < now() - 60m AND time >= "` ~ from.toISOExtString() ~
			`" AND time < "` ~ until.toISOExtString() ~ `"`;
		string queryAnimals = "SELECT time, " ~
			"object_class_name, dead, species, name, " ~
			"pos_x, pos_y, vel_x, vel_y FROM replay_data_animals WHERE " ~
			`simulator_instance = "` ~ simulatorInstance ~ `" AND ` ~
			`time < now() - 60m AND time >= "` ~ from.toISOExtString() ~
			`" AND time < "` ~ until.toISOExtString() ~ `"`;
		auto vesselContent = getContent(m_influxReadUrl, queryParams("epoch", "s", "q", queryVessels));
		auto animalContent = getContent(m_influxReadUrl, queryParams("epoch", "s", "q", queryAnimals));
		JSONValue vesselJson = parseJSON(cast(string) vesselContent.data)["results"][0]["series"][0]["values"];
		JSONValue animalJson = parseJSON(cast(string) animalContent.data)["results"][0]["series"][0]["values"];

		static struct UnifiedReplayObject
		{
			long unixTime;
			ReplayObjectRecord record;
		}

		static UnifiedReplayObject json2URO(JSONValue jv)
		{
			return UnifiedReplayObject(
				jv[0].integer,
				ReplayObjectRecord(
					classNameToROT(jv[1].str),
					jv[2].boolean,
					jv[3].str,
					jv[4].str,
					vec2d(jv[5].floating, jv[6].floating),
					vec2f(jv[7].floating, jv[8].floating)
				));
		}

		/// globally-sorted merged arrays of entities
		auto sortedUROs = merge!((a, b) => a.unixTime < b.unixTime)(
				vesselJson.arrayNoRef.map!(vj => json2URO(vj)),
				animalJson.arrayNoRef.map!(aj => json2URO(aj)));

		ReplaySlice[] res;
		// slice being formed now
		ReplaySlice openedSlice;
		foreach (UnifiedReplayObject uro; sortedUROs)
		{
			if (openedSlice.unixTime == 0)
				openedSlice.unixTime = uro.unixTime;
			if (openedSlice.unixTime != uro.unixTime)
			{
				// new slice has started
				res ~= openedSlice;
				openedSlice = ReplaySlice(uro.unixTime);
			}
			openedSlice.objects ~= uro.record;
		}

		if (openedSlice.objects.length)
			res ~= openedSlice;

		return res;
	}
}
