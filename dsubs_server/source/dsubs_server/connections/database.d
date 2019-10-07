module dsubs_server.connections.database;

import core.thread;

import std.array: array;

import mysql;

import dsubs_server.common;

import dsubs_server.player: Captain, Player;
import dsubs_server.bots: BotCaptain;
import dsubs_server.vessel: Vessel;
import dsubs_server.submarine;
import dsubs_server.torpedo;


struct PlayerDb
{
	string login_name;
	string login_password;
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

	private auto wrapTsac(DlgT)(DlgT dlg)
	{
		try
		{
			Connection con = connection;
			scope(exit) con.close();
			auto res = dlg(con);
		}
		catch (Exception ex)
		{
			error("Error in wrapTsac: ", ex.toString);
		}
	}

	PlayerDb* getPlayerByLogin(string login)
	{
		PlayerDb* func(Connection con)
		{
			Row[] rs = con.query("SELECT login_name, login_password FROM players WHERE " ~
				"login_name = ?", login).array;
			if (rs.length == 0)
				return null;
			return new PlayerDb(rs[0][0].get!string, rs[0][1].get!string);
		}
		return wrapTsac(&func);
	}

	void insertPlayer(string login, string password)
	{
		void func(Connection con)
		{
			con.exec("INSERT INTO players (login_name, login_password) " ~
				"VALUES(?, ?)", login, password);
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

	void insertKillRecord(Captain shooter, Submarine shooterSub, Vessel deadVessel,
		Torpedo weapon)
	{
		Submarine deadSub = cast(Submarine) deadVessel;
		if (deadSub is null)
			return;
		Captain deadCaptain = deadSub.captain;
		void func(Connection con)
		{
			con.exec("INSERT INTO kill_records " ~
				"(shooter_captain_name, shooter_captain_type, shooter_hull_name, " ~
				"dead_captain_name, dead_captain_type, dead_hull_name, weapon_name, " ~
				"weapon_travelled) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
				shooter ? shooter.name: null,
				captainType(shooter),
				shooterSub ? shooterSub.prototypeName : null,
				deadCaptain ? deadCaptain.name: null,
				captainType(deadCaptain),
				deadSub.prototypeName,
				weapon.prototypeName,
				weapon.guidance.distanceTraveled
			);
		}
		wrapTsac(&func);
	}
}