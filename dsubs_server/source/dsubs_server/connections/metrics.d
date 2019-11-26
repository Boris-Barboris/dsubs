module dsubs_server.connections.metrics;

import std.array: Appender, appender;

import requests;

import dsubs_server.common;
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
			error("error writing metrix to influx: ", ex.msg);
		}
	}
}
