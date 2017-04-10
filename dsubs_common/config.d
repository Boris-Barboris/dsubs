module dsubs_common.config;

import std.conv: to;
import std.json;
import std.file;
import std.meta;
import std.traits;

import dsubs_common.reflection;


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

T jsonValueToField(T)(JSONValue tree)
{
	switch (tree.type)
	{
		case JSON_TYPE.STRING: return to!T(tree.str);
		case JSON_TYPE.INTEGER: return to!T(tree.integer);
		case JSON_TYPE.UINTEGER: return to!T(tree.uinteger);
		case JSON_TYPE.FLOAT: return to!T(tree.floating);
		default:
			throw new Exception("can't assing field of type " ~ T.stringof ~
								"from JSONValue of type " ~ 
								to!string(tree.type));
	}
}

void Deserialize(T, FieldFlags flags)(auto ref T obj, JSONValue tree)
{
	//mixin(_Deserilize);
	enum fields = TypeMembers!(T, FieldFlags.Fields)();
	pragma(msg, "struct fields string array ", fields);
	// Iterate over those with Default Value attributes
	foreach (field; aliasSeqOf!(fields))
	{
		// check if it has DefaultValue attribute
		enum attrs = FieldAttributes!(T, field);
		alias fieldType = typeof(mixin("T." ~ field));
		foreach (attr; attrs)
		{
			static if (is (typeof(attr) == DefaultValue!fieldType))
			{
				pragma(msg, "Binding default value of ", attr.default_val, 
					   " to " ~ field);
				mixin("obj." ~ field) = attr.default_val;
			}
		}
		static if (!isAggregateType!fieldType)
		{
			// now assign non-aggregate fields
			pragma(msg, "generating deserialization for ", T, ".", field);
			if (field in tree)
				mixin("obj." ~ field) = jsonValueToField!fieldType(tree[field]);
		}
		else
		{
			// aggregate field - time for recursion
			pragma(msg, "generating aggregate deserialization for ", 
				   T, ".", field);
			JSONValue local_tree = parseJSON(`{}`);
			if (field in tree)
				local_tree = tree[field];
			Deserialize!(fieldType, flags)(mixin("obj." ~ field), local_tree);
		}
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
		Deserialize!(TestConfigJSON, FieldFlags.Fields)(this, tree);
	}

	override string save_to_string() { return "mock"; }
}

unittest
{
	string test_json = `{
		"global_option1": 2,
		"group1": {
			"option1": 3.5,
			"option2": 4,
			"option3": "teststring"
		}
	}`;
	TestConfigJSON config = new TestConfigJSON(test_json);	
	assert(config.global_option1 == 2);
	assert(config.group1.option1 == 3.5);
	assert(config.group1.option2 == 4);
	assert(config.group1.option3 == "teststring");
	assert(config.group1.option4 == 4);
}