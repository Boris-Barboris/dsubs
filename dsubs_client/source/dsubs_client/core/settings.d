module dsubs_client.core.settings;

import std.file;
import std.path;
import std.process: environment;

public import std.json;

import standardpaths;

import dsubs_client.common;


string configFileName()
{
	return buildPath(
		writablePath(
			StandardPath.config, buildPath("dsubs"), FolderFlag.create),
		"dsubs.json");
}


JSONValue readConfig()
{
	try
	{
		string contents = readText(configFileName());
		return parseJSON(contents);
	}
	catch (Exception ex)
	{
		JSONValue res = JSONValue();
		res.object = null;
		return res;
	}
}

void writeConfigField(T)(string key, T newVal)
{
	try
	{
		JSONValue oldConfig = readConfig();
		oldConfig.object[key] = JSONValue(newVal);
		write(configFileName(), toJSON(oldConfig, true));
	}
	catch (Exception ex)
	{
		error("Failed to write config: ", ex.msg);
	}
}