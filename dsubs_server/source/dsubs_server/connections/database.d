module dsubs_server.connections.database;

import core.thread;

import std.algorithm: map;
import std.array: array;
import std.digest.sha: SHA256;
import std.base64: Base64;
import std.uuid: randomUUID, UUID;
import std.typecons: Nullable;
import std.string: representation;
import std.algorithm: equal;

import mysql;
import kdf.pbkdf2;

import dsubs_server.common;

import dsubs_server.player: Captain, Player;
import dsubs_server.bots: BotCaptain;
import dsubs_server.vessel: Vessel, Killable;
import dsubs_server.animal: Animal;
import dsubs_server.submarine;
import dsubs_server.simulator: Simulator;
import dsubs_server.scenario: Scenario;
import dsubs_server.torpedo;


struct PlayerDb
{
	string login_name;
	Nullable!string login_password;
	Nullable!string pw_salt;
	Nullable!string pw_pdkdf2;

	bool passwordMatchesHash(string pw)
	{
		return Base64.decode(pw_pdkdf2.get).equal(
			pbkdf2!SHA256(pw.representation, pw_salt.get.representation));
	}
}


enum SideOutcome: ubyte
{
	defeat,
	victory,
	draw
}


final class DatabaseService
{
	/**
	https://github.com/mysql-d/mysql-native
	auto connectionStr = "host=localhost;port=3306;user=yourname;pwd=pass123;db=mysqln_testdb";
	*/
	this(string mysqlConStr)
	{
		m_mysqlConStr = mysqlConStr;
	}

	private
	{
		string m_mysqlConStr;
	}

	private @property Connection connection()
	{
		return new Connection(m_mysqlConStr);
	}

	/// For login - password pair generate salt and hashed password.
	PlayerDb playerFromLoginPw(string login, Nullable!string password)
	{
		PlayerDb res = PlayerDb(login, password);
		res.pw_salt = randomUUID().toString();
		res.pw_pdkdf2 = Base64.encode(
			pbkdf2!SHA256(password.get.representation, res.pw_salt.get.representation));
		return res;
	}

	/// always new connection is opened, no pooling. Simple and robust on localhost.
	private auto wrapTsac(DlgT)(DlgT dlg)
	{
		try
		{
			Connection con = connection;
			scope(exit) con.close();
			return dlg(con);
		}
		catch (Exception ex)
		{
			error("Error in wrapTsac: ", ex.toString);
			throw ex;
		}
	}

	private static Nullable!string getStringOrNull(T)(T res)
	{
		if (res.type == typeid(typeof(null)))
			return Nullable!string();
		return Nullable!string(res.get!string);
	}

	PlayerDb* getPlayerByLogin(string login)
	{
		PlayerDb* func(Connection con)
		{
			Row[] rs = con.query("SELECT login_name, " ~
				"pw_salt, pw_pdkdf2 FROM players WHERE " ~
				"login_name = ?", login).array;
			if (rs.length == 0)
				return null;
			return new PlayerDb(rs[0][0].get!string, Nullable!string(),
				getStringOrNull(rs[0][1]), getStringOrNull(rs[0][2]));
		}
		return wrapTsac(&func);
	}

	void updatePlayer(PlayerDb pdb)
	{
		void func(Connection con)
		{
			con.exec("UPDATE players SET pw_salt = ?, pw_pdkdf2 = ? " ~
				"WHERE login_name = ?", pdb.pw_salt, pdb.pw_pdkdf2,
					pdb.login_name);
		}
		wrapTsac(&func);
	}

	void insertPlayer(string login, string password)
	{
		PlayerDb pdb = playerFromLoginPw(login, Nullable!string(password));
		void func(Connection con)
		{
			con.exec("INSERT INTO players (login_name, pw_salt, pw_pdkdf2) " ~
				"VALUES(?, ?, ?)", pdb.login_name, pdb.pw_salt, pdb.pw_pdkdf2);
		}
		wrapTsac(&func);
	}

	private static string captainType(Captain cpt)
	{
		if (cpt)
		{
			if (cast(Player) cpt)
				return "player";
			else
				return "bot";
		}
		else
			return null;
	}

	void insertKillRecord(Captain shooter, Submarine shooterSub, Killable deadVessel,
		Torpedo weapon)
	{
		Submarine deadSub = cast(Submarine) deadVessel;
		Animal deadAnimal = cast(Animal) deadVessel;
		if (deadSub is null && deadAnimal is null)
			return;
		string deadCaptainName;
		string deadCaptainType;
		string deadVesselPrototypeName;
		if (deadSub)
		{
			Captain deadCaptain = deadSub.captain;
			deadCaptainName = deadCaptain ? deadCaptain.name: null;
			deadCaptainType = captainType(deadCaptain);
			deadVesselPrototypeName = deadSub.prototypeName;
		}
		else
		{
			deadCaptainName = deadAnimal.name;
			deadCaptainType = "animal";
			deadVesselPrototypeName = deadAnimal.species;
		}
		auto simulator = weapon.simulator;
		void func(Connection con)
		{
			con.exec("INSERT INTO kill_records " ~
				"(shooter_captain_name, shooter_captain_type, shooter_hull_name, " ~
				"dead_captain_name, dead_captain_type, dead_hull_name, weapon_name, " ~
				"weapon_travelled, simulator_id, simulator_uniqid, scenario_name) " ~
				"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
				shooter ? shooter.name: null,
				captainType(shooter),
				shooterSub ? shooterSub.prototypeName : null,
				deadCaptainName,
				deadCaptainType,
				deadVesselPrototypeName,
				weapon.prototypeName,
				weapon.guidance.distanceTraveled,
				simulator.id,
				simulator.uniqId,
				simulator.scenario ? simulator.scenario.name : null
			);
		}
		wrapTsac(&func);
	}

	void insertNewSimulatorInstance(Simulator sim)
	{
		void func(Connection con)
		{
			con.exec(
				"INSERT INTO simulator_instances " ~
				"(uniqid, id, scenario_name, scenario_type) VALUES (?, ?, ?, ?)",
				sim.uniqId, sim.id, sim.scenario ? sim.scenario.name : null,
				sim.scenario ? sim.scenario.scenarioType.to!string : null);
		}
		wrapTsac(&func);
	}

	void markSimulatorDestroyed(string uniqId, string destroyReason)
	{
		void func(Connection con)
		{
			con.exec(
				"UPDATE simulator_instances " ~
				"SET destroyed_at = UTC_TIMESTAMP(), destroy_reason = ? " ~
				"WHERE uniqid = ?",
				destroyReason, uniqId);
		}
		wrapTsac(&func);
	}

	void savePlayerScenarioCompletion(string username, Simulator sim,
		SideOutcome sideOutcome)
	{
		assert(sim.scenario !is null);
		void func(Connection con)
		{
			con.exec(
				"INSERT INTO player_scenario_completions " ~
				"(player_id, scenario_name, scenario_type, simulator_uniqid, " ~
				"side_outcome) VALUES ((SELECT id FROM players WHERE login_name = ?), " ~
				"?, ?, ?, ?)",
				username, sim.scenario.name, sim.scenario.scenarioType.to!string,
				sim.uniqId, sideOutcome.to!string);
		}
		wrapTsac(&func);
	}

	void savePlayerCampaignProgress(string username, string campaignName,
		int completedMissionNumber)
	{
		void func(Connection con)
		{
			con.exec(
				"INSERT INTO player_campaign_progress " ~
				"(player_id, campaign_name, completed_missions) VALUES " ~
				"((SELECT id FROM players WHERE login_name = ?), " ~
				"?, ?) ON DUPLICATE KEY UPDATE " ~
				"completed_missions = GREATEST(completed_missions, ?)",
				username, campaignName, completedMissionNumber, completedMissionNumber);
		}
		wrapTsac(&func);
	}
}