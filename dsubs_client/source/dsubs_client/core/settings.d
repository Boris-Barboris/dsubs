module dsubs_client.core.settings;

import std.file;
import std.path;
import std.process: environment;

public import std.json;


version(Windows)
{
	string configFileName()
	{
		return "%LOCALAPPDATA%\\dsubs.json";
	}
}
version(Posix)
{
	string configFileName()
	{
		return expandTilde(environment.get("XDG_CONFIG_HOME", "~/.config") ~ "/dsubs.json");
	}
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
	JSONValue oldConfig = readConfig();
	oldConfig.object[key] = JSONValue(newVal);
	write(configFileName(), toJSON(oldConfig, true));
}