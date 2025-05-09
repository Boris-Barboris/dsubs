/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.objfile;

import std.algorithm: startsWith, splitter, sort, joiner;
import std.ascii: isWhite;
import std.array: Appender;
import std.format: format;
import std.path;
import std.file: read, write;
import std.regex: regex, matchFirst;
import std.range: iota, retro;
import std.string: lineSplitter;

import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.submarine: Submarine2DModel;



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


float blenderSrgb2Linear(float c)
{
	if (c < 0.04045f)
		return (c < 0.0f) ? 0.0f : c * (1.0f / 12.92f);
	return pow((c + 0.055f) * (1.0f / 1.055f), 2.4f);
}

float blenderLinear2Srgb(float c)
{
	if (c < 0.0031308f)
		return (c < 0.0f) ? 0.0f : c * 12.92f;
	return 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
}

ubyte floatToUbyteColor(float color)
{
	return (blenderLinear2Srgb(color) * ubyte.max).to!ubyte;
}

float ubyteToFloatColor(ubyte color)
{
	return blenderSrgb2Linear(color / 255.0f);
}


ObjModel readModelFromObj(string filename, string directory = "models/")
{
	string filepath = buildPath(directory, filename);
	trace("loading .obj file ", filepath);
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
			// Blender randomly names objects like techhole as techhole_Plane.012
			string objName = faceFilled.objectName;
			auto r = regex("(.+)_Plane.*");
			auto m = matchFirst(objName, r);
			if (!m.empty)
				objName = m[1];
			// only first face of the object gets into allFaces dict
			if ((objName in res.allFaces) is null)
				res.allFaces[objName] = faceFilled;
			continue;
		}
	}

	// Z-order sorting
	res.faces.sort!((a, b) => a.depth < b.depth);

	// now we parse material file
	enforce(mtlibName.length > 0, "Didn't find mtllib in .obj file");
	// mtl lib must be in the same folder as .obj file
	string matfilepath = buildPath(dirName(filepath), mtlibName);
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
		enforce(face.materialName in res.materials,
			"material reference broken: " ~ face.materialName);
	}

	// trace("loaded model ", res);

	return res;
}


// TODO: write an inverse function that dumps Submarine2DModel to obj and mat files

private void dumpPolygonToPlane(
	ref Appender!string planeBuf, ref Appender!string materialBuf, ref int faceCounter,
	ConvexPolygon polygon, float zdepth, string planeName, string materialName)
{
	planeBuf.put("o ");
	planeBuf.put(planeName);
	planeBuf.put('\n');
	foreach (point; polygon.points.retro)
	{
		string vertexString = format("v %f6 %f6 %f6\n", point.x, point.y, zdepth);
		planeBuf.put(vertexString);
	}
	planeBuf.put("usemtl ");
	planeBuf.put(materialName);
	planeBuf.put('\n');
	planeBuf.put("s off\n");
	planeBuf.put("f ");
	planeBuf.put(
		iota(1, polygon.points.length + 1).map!(n => (n + faceCounter).to!string).
		joiner(" "));
	faceCounter += polygon.points.length;
	planeBuf.put("\n\n");
	materialBuf.put("newmtl ");
	materialBuf.put(materialName);
	materialBuf.put('\n');
	materialBuf.put("Ns 323.999994
Ka 1.000000 1.000000 1.000000\n");
	string colorString =
		format("Kd %f6 %f6 %f6\n",
			ubyteToFloatColor(polygon.fillColor.r),
			ubyteToFloatColor(polygon.fillColor.g),
			ubyteToFloatColor(polygon.fillColor.b));
	materialBuf.put(colorString);
	materialBuf.put("Ks 0.500000 0.500000 0.500000
Ke 0.000000 0.000000 0.000000
Ni 1.000000
d 1.000000
illum 2\n\n");
}

private void dumpSpecialMountPointToPlane(ref Appender!string planeBuf,
	ref int faceCounter, vec2f point, float zdepth, string planeName)
{
	planeBuf.put("o ");
	planeBuf.put(planeName);
	planeBuf.put('\n');
	// square with 1m edge
	vec2f[] square = [
		vec2f(point.x + 0.4f, point.y + 0.4f),
		vec2f(point.x + 0.4f, point.y - 0.4f),
		vec2f(point.x - 0.4f, point.y - 0.4f),
		vec2f(point.x - 0.4f, point.y + 0.4f)
	];
	foreach (p; square)
	{
		string vertexString = format("v %f6 %f6 %f6\n", p.x, p.y, zdepth);
		planeBuf.put(vertexString);
	}
	planeBuf.put("usemtl None\n");
	planeBuf.put("s off\n");
	planeBuf.put("f ");
	planeBuf.put(
		iota(1, 5).map!(n => (n + faceCounter).to!string).joiner(" "));
	faceCounter += 4;
	planeBuf.put('\n');
}

// filename without extention!
void dumpSubmarine2DModel(string filename, Submarine2DModel subModel,
	MountPoint[] propulsorMountPoints, ConvexPolygon[] propulsorModels,
	MountPoint[] hydrophoneMounts, MountPoint[] activeSonarMounts,
	MountPoint[] tubeMounts)
{
	Appender!string objBuf = Appender!string(null);
	Appender!string materialBuf = Appender!string(null);
	int faceCounter;
	int firstPositiveZIdx = subModel.elevatedHullShapeIdx;
	enforce(firstPositiveZIdx >= 0 && firstPositiveZIdx < subModel.hullModel.length);
	for (int i = 0; i < subModel.hullModel.length; i++)
	{
		float zlevel = (i - firstPositiveZIdx + 1) * 0.1f;
		string planeName = "plane" ~ i.to!string;
		dumpPolygonToPlane(objBuf, materialBuf, faceCounter, subModel.hullModel[i],
			zlevel, planeName ~ "_Plane", planeName ~ "_mat");
	}
	// propulsor models
	foreach (i, propulsorModel; propulsorModels)
	{
		propulsorModel.points = propulsorModel.points.dup;
		// offset by first propulsor mount point
		foreach (ref point; propulsorModel.points)
			point += propulsorMountPoints[0].mountCenter;
		string screwName = "_screw" ~ i.to!string;
		dumpPolygonToPlane(objBuf, materialBuf, faceCounter, propulsorModel, 0.0f,
				screwName ~ "_Plane", screwName ~ "_mat");
	}

	void writeSpecialMountPoints(MountPoint[] mounts, string name)
	{
		foreach (i, mount; mounts)
		{
			dumpSpecialMountPointToPlane(objBuf, faceCounter, mount.mountCenter, 0.05f,
				name ~ i.to!string ~ "_Plane");
		}
	}
	writeSpecialMountPoints(propulsorMountPoints, "_propulsor");
	writeSpecialMountPoints(hydrophoneMounts, "_hydrophone");
	writeSpecialMountPoints(activeSonarMounts, "_activesonar");
	writeSpecialMountPoints(tubeMounts, "_tube");

	write(filename ~ ".obj", objBuf.data());
	write(filename ~ ".mtl", materialBuf.data());
}