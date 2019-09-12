module dsubs_server.connections.metrics;

import requests;

import dsubs_server.common;


final class MetricsService
{
	private string m_influxUrl;

	/// https://docs.influxdata.com/influxdb/v1.7/write_protocols/line_protocol_tutorial/#writing-data-to-influxdb
	/// influxUrl example: http://localhost:8086/write?db=science_is_cool
	this(string influxUrl)
	{
		m_influxUrl = influxUrl;
	}

	void writeMetrics(long usecsSimStep, int connectedPlayers)
	{
		try
		{
			postContent(m_influxUrl,
				"simulator_stats total_usecs=" ~ usecsSimStep.to!string ~ "\n" ~
				"player_stats connected_players=" ~ connectedPlayers.to!string);
		}
		catch (Exception ex)
		{
			error("error writing metrix to influx: ", ex.msg);
		}
	}
}
