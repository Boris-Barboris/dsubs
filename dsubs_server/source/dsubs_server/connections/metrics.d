module dsubs_server.connections.metrics;

import std.range: replace;
import std.array: Appender, appender;

import requests;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.animal;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.player;
import dsubs_server.scenario;
import dsubs_common.proftimer;


final class MetricsService
{
	private string m_influxUrl;

	/// https://docs.influxdata.com/influxdb/v1.7/write_protocols/line_protocol_tutorial/#writing-data-to-influxdb
	/// influxUrl example: http://localhost:8086/write?db=science_is_cool
	this(string influxUrl)
	{
		m_influxUrl = influxUrl;
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
					if (sub && sub.captain)
					{
						strBuf ~= ",captain_name=" ~ quote(sub.captain.name);
					}
					else
						strBuf ~= ",captain_name=null";
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
}
