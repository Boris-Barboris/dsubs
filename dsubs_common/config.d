module config;

import std.conv: to;
import std.json;
import std.file;

/// Class that manages one configuration file
class ConfigJson
{
	JSONValue root;
	const string filename;

	this(string filename)
	{
		this.filename = filename;
		string content = readText(filename);
		root = parseJSON(content);
	}
}

string json_type(string type)
{
	switch (type)
	{
		case "string": return "str";
		case "long": return "integer";
		case "ulong": return "uinteger";
		case "double": return "floating";
		default: 
			assert(false);
	}
}

abstract class ConfigGroup(string group_name_static)
{
	static immutable group_name = group_name_static;
	protected ConfigJson CONF;

	this(ConfigJson config)
	{
		CONF = config;
	}

	mixin template ConfigOption(T, string opt_name)
	{
		mixin("@property " ~ T.stringof ~ " " ~ opt_name ~ 
			  "() { return CONF.root[\"" ~ group_name ~ "\"][\"" ~ opt_name ~
			  "\"]." ~ json_type(T.stringof) ~ "; }");
		mixin("@property " ~ T.stringof ~ " " ~ opt_name ~ 
			  "(" ~ T.stringof ~ " value) { return CONF.root[\"" ~ group_name ~ "\"][\"" ~ opt_name ~
			  "\"]." ~ json_type(T.stringof) ~ "(value); }");
	}
}


/// test config group
private class TestConfigGroup: ConfigGroup!("testGroup")
{
	this(ConfigJson config) { super(config); }

	mixin ConfigOption!(string, "some_string_option");
	mixin ConfigOption!(double, "some_double_option");
}