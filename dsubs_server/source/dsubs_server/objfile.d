module dsubs_server.objfile;

import std.algorithm: startsWith, splitter, sort;
import std.ascii: isWhite;
import std.path;
import std.file: read;
import std.regex: regex, matchFirst;
import std.string: lineSplitter;

import dsubs_common.api.entities;

import dsubs_server.common;



struct ObjModel
{
	ObjMaterial[string] materials;
	/// visible faces, sorted by depth
	ObjFace[] faces;
	ObjFace[string] allFaces;
}

struct ObjFace
{
	string objectName;
	vec2f[] points;
	float depth;
	string materialName;

	/// center of points, geometric mean
	@property vec2f center() const
	{
		vec2f res = vec2f(0.0f, 0.0f);
		foreach (point; points)
			res += point;
		res /= points.length;
		return res;
	}
}

struct ObjMaterial
{
	string name;
	RgbaColor color;
}


ubyte floatToUbyteColor(float color)
{
	float blenderGamma = 1.0f / 2.2f;
	return (pow(color, blenderGamma) * ubyte.max).to!ubyte;
}


ObjModel readModelFromObj(string filename, string directory = "models/")
{
	string filepath = buildPath(directory, filename);
	string fileContents = cast(string) read(filepath);

	ObjModel res;
	ObjFace faceFilled;
	vec2f[] vertices;
	string mtlibName;

	// iterate over lines of obj file
	foreach (string line; lineSplitter(fileContents))
	{
		if (line.length == 0 || line[0] == '#' || isWhite(line[0]))
			continue;
		if (line.startsWith("mtllib "))
		{
			mtlibName = line.splitter(" ").array[1];
			continue;
		}
		if (line.startsWith("o "))
		{
			faceFilled.objectName = line.splitter(" ").array[1];
			continue;
		}
		if (line.startsWith("v "))
		{
			vec2f vertex;
			string[] splitResults = line.splitter(" ").array;
			vertex = vec2f(splitResults[1].to!float, splitResults[2].to!float);
			vertices ~= vertex;
			faceFilled.depth = splitResults[3].to!float;
			continue;
		}
		if (line.startsWith("usemtl "))
		{
			faceFilled.materialName = line.splitter(" ").array[1];
			continue;
		}
		if (line.startsWith("f "))
		{
			string[] splitResults = line.splitter(" ").array;
			faceFilled.points.length = 0;
			// face is finalized
			for (size_t i = 1; i < splitResults.length; i++)
			{
				size_t vertexIdx = splitResults[i].to!size_t;
				faceFilled.points ~= vertices[vertexIdx - 1];
			}
			// objects that start from underscore are not rendered
			if (faceFilled.objectName[0] != '_')
				res.faces ~= faceFilled;
			// typical name
			auto r = regex("(.+)_Plane.*");
			auto m = matchFirst(faceFilled.objectName, r);
			if (m.empty)
				throw new Exception("object name " ~ faceFilled.objectName ~
					" does not match *_Plane* pattern");
			res.allFaces[m[1]] = faceFilled;
			continue;
		}
	}

	// Z-order sorting
	res.faces.sort!((a, b) => a.depth < b.depth);

	// now we parse material file
	string matfilepath = buildPath(directory, mtlibName);
	fileContents = cast(string) read(matfilepath);

	ObjMaterial materialFilled;

	// iterate over lines of obj file
	foreach (string line; lineSplitter(fileContents))
	{
		if (line.length == 0 || line[0] == '#' || isWhite(line[0]))
			continue;
		if (line.startsWith("newmtl "))
		{
			materialFilled.name = line.splitter(" ").array[1];
			continue;
		}
		if (line.startsWith("Kd "))
		{
			RgbaColor color;
			string[] splitResults = line.splitter(" ").array;
			color.r = splitResults[1].to!float.floatToUbyteColor;
			color.g = splitResults[2].to!float.floatToUbyteColor;
			color.b = splitResults[3].to!float.floatToUbyteColor;
			materialFilled.color = color;
			// material is finalized
			res.materials[materialFilled.name] = materialFilled;
			continue;
		}
	}

	// validate material references
	foreach (face; res.faces)
	{
		enforce(face.materialName in res.materials, "materials not consistent");
	}

	// trace("loaded model ", res);

	return res;
}