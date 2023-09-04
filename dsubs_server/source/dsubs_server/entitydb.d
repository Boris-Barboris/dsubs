module dsubs_server.entitydb;

import core.sync.mutex: Mutex;

import std.array: array;
import std.algorithm: map, any, filter, endsWith;
import std.digest.sha;
import std.range: retro;
import std.json;
import std.file: write, readText, dirEntries, SpanMode;
import std.typecons: Nullable;
import std.exception;

import dsubs_common.api;
import dsubs_common.api.messages;
import dsubs_common.api.marshalling;
import dsubs_common.json;
import dsubs_common.lockmap;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.water: seaNoiseIL, flowNoise;
import dsubs_sound.hydrophone;
import dsubs_sound.modulation;
import dsubs_sound.soundsource;
import dsubs_sound.image;
import dsubs_sound.opencl: CommandQueue;
import dsubs_sound.common: GLOBAL_SRATE;

import dsubs_server.common;
import dsubs_server.acoustics: JukeboxSoundTimings, PrerecordedSoundConfig,
	SpectrumImageConfig;
import dsubs_server.objfile;
import dsubs_server.propulsion;
import dsubs_server.sensors;
import dsubs_server.dynamics;
import dsubs_server.player: Captain;
import dsubs_server.vessel: MountPointConfig, VesselFactoryConfig;
public import dsubs_server.submarine;
public import dsubs_server.animal;
public import dsubs_server.torpedo;
public import dsubs_server.weaponry;


alias EntityDbStruct = dsubs_common.api.entities.EntityDb;



final class EntityDb
{
	/// pre-marshalled entity database message, ready to be send to user.
	const immutable(ubyte)[] marshalledCommonEntityDb;

	/// hash (SHA-256) of marshalledCommonEntityDb
	const immutable(ubyte)[] commonEntityDbHash;

	private
	{
		/// map of all existing propulsor factories
		PropulsorFactory[string] m_propulsors;
		/// global map of all existing submarine factories
		SubmarineFactory[string] m_submarines;
		/// global map of all existing torpedo/decoy factories
		WeaponFactory[string] m_weapons;
		/// global map of all existing animal factories
		AnimalFactory[string] m_animals;
		/// global map of filename->parsed_model
		ObjModel*[string] m_models;
	}

	/// Get EntityDbShort that contains all playable entities.
	EntityDbShort getCompleteShortDb() const
	{
		EntityDbShort res;
		res.controllableSubNames = cast(string[]) m_submarines.byValue.filter!(sf => sf.playable).
			map!(sf => sf.name).array;
		res.propulsorNames = cast(string[]) m_propulsors.byValue.filter!(pf => pf.playable).
			map!(pf => pf.name).array;
		res.weaponNames = cast(string[]) m_weapons.byValue.filter!(wf => wf.playable).
			map!(wf => wf.name).array;
		return res;
	}

	PropulsorFactory getPropulsorFactory(string name)
	{
		return m_propulsors[name];
	}

	SubmarineFactory getSubmarineFactory(string name)
	{
		return m_submarines[name];
	}

	WeaponFactory getWeaponFactory(string name)
	{
		return m_weapons[name];
	}

	AnimalFactory getAnimalFactory(string name)
	{
		return m_animals[name];
	}

	const(WeaponFactory) getWeaponFactory(string torpName) const
	{
		return m_weapons[torpName];
	}

	private Mutex m_objModelsMutex;
	private LockMap m_objModelsLockMap;

	ObjModel* getObjModel(string filename)
	{
		ObjModel** model;
		synchronized(m_objModelsMutex)
		{
			model = filename in m_models;
			if (model)
				return *model;
		}
		synchronized(m_objModelsLockMap.get(filename))
		{
			synchronized(m_objModelsMutex)
			{
				model = filename in m_models;
				if (model)
					return *model;
			}
			ObjModel* res = new ObjModel();
			assert(filename.length > 0, "len of filename is wrong: " ~ filename);
			*res = readModelFromObj(filename, "");
			synchronized(m_objModelsMutex)
			{
				m_models[filename] = res;
				return res;
			}
		}
	}

	Submarine2DModel loadSubModel(string filename, out ObjModel* obj)
	{
		obj = getObjModel(filename);
		Submarine2DModel res;
		bool elevatedFound;

		ConvexPolygon polygonBuilt;

		foreach (i, face; obj.faces)
		{
			if (!elevatedFound && face.depth > 1e-3f)
			{
				elevatedFound = true;
				res.elevatedHullShapeIdx = i.to!int;
			}
			polygonBuilt.points = face.points;
			polygonBuilt.fillColor = obj.materials[face.materialName].color;
			vec2f dims = getPolygonDims(polygonBuilt);
			polygonBuilt.borderWidth = autoBorderWidth(dims);
			polygonBuilt.borderColor = autoBorderColor(polygonBuilt.fillColor);
			res.hullModel ~= polygonBuilt;
		}

		return res;
	}

	this()
	{
		m_objModelsMutex = new Mutex();
		m_objModelsLockMap = new LockMap();
		info("Building entity database");
		loadFromDirectory("entitydb/");
		preloadScenarioSounds();
		sanityCheckDb();
		immutable EntityDbStruct enititydb = immutable EntityDbStruct(
			m_propulsors.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
			m_submarines.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
			m_weapons.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
		);
		marshalledCommonEntityDb = BackendProtocol.marshal(immutable EntityDbRes(enititydb));
		auto sha256 = new SHA256Digest();
		sha256.put(marshalledCommonEntityDb);
		commonEntityDbHash = cast(immutable(ubyte)[]) sha256.finish();
		assert(commonEntityDbHash.length == 32);
	}

	/// Build submarine object from the Spawn request message
	Submarine buildSubFromLoadout(const SpawnReq req, Captain cpt, bool humanPlayer = false)
	{
		SubmarineFactory* sf = req.submarineName in m_submarines;
		enforce(sf !is null, "Unknown submarine");
		if (humanPlayer)
			enforce(sf.playable, "sub is unplayable");
		PropulsorFactory* pf = req.propulsorName in m_propulsors;
		enforce(pf !is null, "Unknown propulsor");
		if (humanPlayer)
			enforce(pf.playable, "propulsor is unplayable");
		enforce(sf.tmpl.propulsors.any!(p => p == pf.tmpl.name)(),
			"Propulsor not allowed for submarine");
		Propulsor[] propulsors;
		for (int i = 0; i < sf.propulsionMounts.length; i++)
			propulsors ~= pf.build();
		Submarine sub = sf.build(cpt, propulsors, req.ammoRoomLoadouts,
			req.loadableTubeLoadouts);
		trace("built new submarine from request ", req);
		return sub;
	}

	void loadFromDirectory(string dirPath = "entitydb/")
	{
		string[] jsonFilePaths;
		foreach (entry; dirEntries(dirPath, SpanMode.depth))
		{
			if (entry.isFile && entry.name.endsWith(".json"))
				jsonFilePaths ~= entry.name;
		}
		foreach (filePath; Globals.taskPool.parallel(jsonFilePaths, 1))
		{
			trace("Loading json config ", filePath);
			try
			{
				string jsonText = readText(filePath);
				JSONValue parsed = parseJSON(jsonText);
				enforce(parsed.type == JSONType.object, "expected object type");
				string entityType = parsed["entityType"].get!string;
				int workerIdx = Globals.taskPool.workerIndex.to!int;
				auto q = Globals.sctx.queue(workerIdx);
				switch (entityType)
				{
					case "Submarine":
						loadSubmarine(parsed);
						break;
					case "Propulsor":
						loadPropulsor(parsed, q);
						break;
					case "Torpedo":
						loadTorpedo(parsed);
						break;
					case "ActiveDecoy":
						loadActiveDecoy(parsed);
						break;
					case "PassiveDecoy":
						loadPassiveDecoy(parsed);
						break;
					case "Animal":
						loadAnimal(parsed);
						break;
					default:
						info("Skipping unsupported entity type ", entityType);
				}
			}
			catch (Throwable ex)
			{
				error("Failure during entity load from ", filePath, ": ", ex.toString());
				throw ex;
			}
		}
		// late binding of weapons to propulsors
		foreach (weaponFactory; Globals.taskPool.parallel(m_weapons.byValue, 1))
		{
			if (auto wf = cast(WeaponFactoryWithPropulsor) weaponFactory)
			{
				enforce(wf.propulsorName in m_propulsors,
					"Unresolved propulsor reference " ~ wf.propulsorName ~ " in " ~ wf.name);
				wf.prepareDynamicsAndParams(m_propulsors[wf.propulsorName]);
			}
		}
	}

	void sanityCheckDb()
	{
		foreach (subFactory; m_submarines.byValue)
		{
			scope(failure) error("Sanity check for ", subFactory.name, " failed");
			foreach (propName; subFactory.allowedPropulsors)
				enforce(propName in m_propulsors,
					"Propulsor reference " ~ propName ~ " is unsatisfied");
			foreach (roomProto; subFactory.roomProtos)
			{
				foreach (wpnName; roomProto.allowedWeaponSet)
					enforce(wpnName in m_weapons,
						"Weapon reference " ~ wpnName ~ " is unsatisfied");
			}
		}
	}


private:

	void loadPropulsor(const JSONValue jv, CommandQueue q)
	{
		PropulsorFactoryConfig fc;
		deserializeJson(fc, jv);
		PropulsorFactory pf = new PropulsorFactory();
		pf.propulsorConfig = fc;
		pf.propulsorConfig.soundPrototypeConfig.loadPrototype(q);
		if (!fc.modelConfig.isNull)
		{
			pf.model = screwModelFromFace(
				fc.modelConfig.get.screwFaceName, fc.modelConfig.get.shaftPointName,
				*getObjModel(fc.modelConfig.get.objModelFilename));
		}
		synchronized(this)
		{
			m_propulsors[pf.name] = pf;
		}
		trace("Finished loading Propulsor ", pf.name);
		info(pf.name, " cavitates on throttle ",
			PropellerSound.estCavitationShaftFreq(pf.soundPrototype) / pf.shaftRotFreq);
	}

	void loadAnimal(const JSONValue jv)
	{
		AnimalFactory af = new AnimalFactory();
		deserializeJson(af.animalConfig, jv);
		foreach (ref randomSound; af.randomSoundConfigs)
			randomSound.buildPrototype(Globals.sctx);
		synchronized(this)
		{
			m_animals[af.species] = af;
		}
		trace("Finished loading Animal ", af.species);
	}

	void loadTorpedo(const JSONValue jv)
	{
		TorpedoFactory tf = new TorpedoFactory();
		deserializeJson(tf.torpedoConfig, jv);
		if (tf.detonationSoundProto.tdsFilename.length > 0)
			tf.detonationSoundProto.buildPrototype(Globals.sctx);
		synchronized(this)
		{
			m_weapons[tf.name] = tf;
		}
		trace("Finished loading Torpedo ", tf.name);
	}

	void loadActiveDecoy(const JSONValue jv)
	{
		ActiveDecoyFactory tf = new ActiveDecoyFactory();
		deserializeJson(tf.activeDecoyConfig, jv);
		tf.generateParamDescs();
		synchronized(this)
		{
			m_weapons[tf.name] = tf;
		}
		trace("Finished loading ActiveDecoy ", tf.name);
	}

	void loadPassiveDecoy(const JSONValue jv)
	{
		PassiveDecoyFactory tf = new PassiveDecoyFactory();
		deserializeJson(tf.passiveDecoyConfig, jv);
		synchronized(this)
		{
			m_weapons[tf.name] = tf;
		}
		trace("Finished loading PassiveDecoy ", tf.name);
	}

	void loadSubmarine(const JSONValue jv)
	{
		SubmarineFactoryConfig fc;
		fc.vesselConfig = new VesselFactoryConfig();
		deserializeJson(fc, jv);
		SubmarineFactory sf = new SubmarineFactory();
		sf.vesselConfig = fc.vesselConfig;
		sf.name = fc.name;
		sf.description = fc.description;
		sf.allowedPropulsors = fc.allowedPropulsors;
		sf.playable = fc.playable;
		foreach (roomProto; fc.ammoRooms)
			sf.roomProtos[roomProto.id] = roomProto;
		if (fc.model.modelFileName.length > 0)
		{
			ObjModel* objModel;
			sf.model = loadSubModel(fc.model.modelFileName, objModel);
			foreach (ref mountConfig; fc.propulsionMounts)
				mountConfig.setCenterFromModel(*objModel);
			foreach (ref hydroProto; fc.hydrophones)
				hydroProto.mount.setCenterFromModel(*objModel);
			foreach (ref sonarProto; fc.activeSonars)
				sonarProto.mount.setCenterFromModel(*objModel);
			foreach (ref tubeConfig; fc.tubes)
				tubeConfig.setCenterFromModel(*objModel);
		}
		foreach (ref tubeConfig; fc.tubes)
			tubeConfig.buildSoundProtos(Globals.sctx);
		sf.propulsionMounts = fc.propulsionMounts.map!(mpc => mpc.mountPoint).array;
		sf.hprots = fc.hydrophones;
		enforce(fc.activeSonars.length <= 1,
			"engine does not support multiple active sonars");
		sf.asprot = fc.activeSonars ? &fc.activeSonars[0] : null;
		foreach (tubeProto; fc.tubes)
		{
			sf.tubeProtos[tubeProto.tmpl.id] = tubeProto;
		}
		// FIXME: more granular lock
		synchronized(this)
		{
			m_submarines[sf.name] = sf;
		}
		trace("Finished loading Submarine ", sf.name);
	}

	void preloadScenarioSounds()
	{
		Globals.sctx.getWavFile("../dsubs_sound/scenario_sounds/man_screaming1.wav");
		Globals.sctx.getWavFile("../dsubs_sound/scenario_sounds/man_screaming2.wav");
		Globals.sctx.getWavFile("../dsubs_sound/scenario_sounds/man_screaming3.wav");
		Globals.sctx.getWavFile(
			"../dsubs_sound/scenario_sounds/Monrroe - Out of Time (feat. Zara Kershaw).wav");
		Globals.sctx.getWavFile(
			"../dsubs_sound/scenario_sounds/Epiphany-TwoThirds.wav");
		Globals.sctx.getWavFile("../dsubs_sound/scenario_sounds/sos.wav");
	}

}


private:

/// build vec2f array from float array
vec2f[] arr2vec2f(const float[] coords)
{
	assert(coords.length >= 2);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	vec2f[] res;
	for (int i = 0; i < len; i++)
		res ~= vec2f(coords[i*2], coords[i*2 + 1]);
	return res;
}

/// build axially-symmetric mesh from it's half. 'coords' array should be in form
/// [ x1, y1, x2, y2 ... ]
vec2f[] xSymmetry(const float[] coords, bool firstAsMirrorX = false)
{
	assert(coords.length >= 4);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	vec2f[] res;
	float xPivot = firstAsMirrorX ? coords[0] : 0.0f;
	for (int i = 0; i < len; i++)
		res ~= vec2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= vec2f(xPivot - coords[i*2], coords[i*2 + 1]);
	return res;
}

/// assume that coords describe a complete shape and reflect it
vec2f[] xreflect(const vec2f[] coords)
{
	return coords.retro.map!(c => vec2f(-c.x, c.y)).array;
}

vec2f getHullDims(const ConvexPolygon[] pols)
{
	float xmin = float.max;
	float xmax = -float.max;
	float ymin = float.max;
	float ymax = -float.max;
	foreach (pol; pols)
	{
		foreach (vec; pol.points)
		{
			if (xmin > vec[0])
				xmin = vec[0];
			if (xmax < vec[0])
				xmax = vec[0];
			if (ymin > vec[1])
				ymin = vec[1];
			if (ymax < vec[1])
				ymax = vec[1];
		}
	}
	return vec2f(xmax - xmin, ymax - ymin);
}

vec2f getPolygonDims(const ConvexPolygon pol)
{
	float xmin = float.max;
	float xmax = -float.max;
	float ymin = float.max;
	float ymax = -float.max;
	foreach (vec; pol.points)
	{
		if (xmin > vec[0])
			xmin = vec[0];
		if (xmax < vec[0])
			xmax = vec[0];
		if (ymin > vec[1])
			ymin = vec[1];
		if (ymax < vec[1])
			ymax = vec[1];
	}
	return vec2f(xmax - xmin, ymax - ymin);
}


// automatically calculate border width
float autoBorderWidth(vec2f dims)
{
	float minDim = dims.x;
	if (dims.y < minDim)
		minDim = dims.y;
	return minDim > 5.0f ? 0.25f : (0.25f / 5.0f * minDim);
}


RgbaColor autoBorderColor(RgbaColor fillColor)
{
	RgbaColor res = fillColor;

	static ubyte highlight(ubyte fillColor)
	{
		int addition = 30 + fillColor / 6;
		return (min(ubyte.max, fillColor + addition)).to!ubyte;
	}

	res.r = highlight(res.r);
	res.g = highlight(res.g);
	res.b = highlight(res.b);
	return res;
}


ConvexPolygon screwModelFromFace(string screwFaceName, string shaftPointName,
	const ref ObjModel model)
{
	ConvexPolygon res;
	const ObjFace face = model.allFaces[screwFaceName];
	const ObjFace refFace = model.allFaces[shaftPointName];
	res.points = face.points.dup;
	// offset points to move Y coordinate to zero
	vec2f offset = refFace.center;
	foreach (ref vec2f point; res.points)
		point -= offset;
	res.fillColor = model.materials[face.materialName].color;
	res.borderColor = autoBorderColor(res.fillColor);
	res.borderWidth = autoBorderWidth(getPolygonDims(res));
	return res;
}

void dumpSubConfig(string filename, SubmarineFactoryConfig config)
{
	auto j = config.toJson();
	j["entityType"] = "Submarine";
	write(filename, j.toPrettyString());
}

void dumpPropulsorConfig(string filename, PropulsorFactoryConfig config)
{
	auto j = config.toJson();
	j["entityType"] = "Propulsor";
	write(filename, j.toPrettyString(JSONOptions.specialFloatLiterals));
}

void dumpWeaponConfig(string filename, VesselFactoryConfig config, string entityType)
{
	auto j = config.toJsonDynamic();
	j["entityType"] = entityType;
	write(filename, j.toPrettyString(JSONOptions.specialFloatLiterals));
}

void dumpAnimalConfig(string filename, AnimalFactoryConfig config)
{
	auto j = config.toJson();
	j["entityType"] = "Animal";
	write(filename, j.toPrettyString(JSONOptions.specialFloatLiterals));
}