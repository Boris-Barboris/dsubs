module config;

import std.conv: to;
import std.json;
import std.file;

import reflection;


class Config
{
	abstract void load();
	abstract void save();
}

// This config has empty body, so you better be
abstract class ConfigJSON: Config
{
	const string _filename;

	this(string filename)
	{
		this._filename = filename;
	}

	protected JSONValue _tree;

	override void load()
	{
		string file_content = readText(_filename);
		_tree = parse(file_content);
		load_from_jsonvalue(_tree);
	}

	// load from string content
	protected abstract void load_from_jsonvalue(JSONValue value);

	abstract string save_to_string();

	static JSONValue parse(string content) { return parseJSON(content); }

	override void save()
	{
		string file_content = save_to_string();
		write(_filename, file_content);
	}
}

// Attribute to hang on fields wich have default values
struct DefaultValue(T)
{
	T default_val;
	this(T val) { default_val = val; }
}

// this function deserializes field from json
void jsonToField(GroupType, FieldType, string field_name)
				(JSONValue json, ref FieldType field)
{
	// check if field is not internal json config field
	static if (field_name == "_tree" || field_name == "_filename")
		return;
	// check if it is struct

	// check if it is present in JSONValue
	if (field_name in json)
	{
		// assign and return;
		enum getter = json_getter!(FieldType)();
		pragma(msg, "binding json[field_name]." ~ getter ~ " to " ~ field_name);
		FieldType val = to!FieldType(mixin("json[field_name]." ~ getter));
		field = val;
		return;
	}
	else
	{
		// maybe field has attribute assigned to it
		enum attrs = __traits(getAttributes, 
			mixin(GroupType.stringof ~ "." ~ field_name));
		pragma(msg, "Attributes ", attrs);
		foreach (attr; attrs)
		{
			if (is (attr == DefaultValue!(FieldType)))
			{
				pragma(msg, "Binding default value of ", attr.default_val, 
					   " to " ~ field_name);
				field = attr.default_val;
				break;
			}
		}
		return;
	}
}

string json_getter(fieldType)()
{
	string typeName = fieldType.stringof;
	switch (typeName)
	{
		case "double": return "floating";
		case "ulong": return "uinteger";
		case "unsigned": return "uinteger";
		case "long": return "integer";
		case "int": return "integer";
		case "string": return "str";
		default: return "_ErrorType";
	}
}


// tests

private struct TestConfigGroup
{
	double option1;
	int option2;
	string option3;

	@(DefaultValue!(int)(4))
	int option4;
}

private class TestConfigJSON: ConfigJSON
{
	this(string content)
	{
		super("mock");
		_tree = parse(content);
		load_from_jsonvalue(_tree);
	}

	// global field
	int global_option1;
	// groups
	TestConfigGroup group1;

	override void load_from_jsonvalue(JSONValue tree)
	{
		// we need to iterate over our fields
		//immutable auto fields = __traits(allMembers, TestConfigJSON);
		//enum fields = TypeFields!(TestConfigJSON, FieldFlags.Fields)();
		//pragma(msg, "fields string array", fields);

		jsonToField!(TestConfigGroup, int, "option4")(tree, group1.option4);
		jsonToField!(TestConfigJSON, int, "global_option1")(tree, global_option1);
	}

	override string save_to_string() { return "mock"; }
}

unittest
{
	TestConfigJSON config = new TestConfigJSON("{}");
}