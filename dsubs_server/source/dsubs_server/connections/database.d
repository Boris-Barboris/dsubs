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
		Connection m_con;
	}

	private @property Connection connection()
	{
		if (m_con)
			return m_con;
		m_con = new Connection(m_mysqlConStr);
		return m_con;
	}

	private auto wrapInRetry(DlgT)(DlgT dlg)
	{
		synchronized(this)
		{
			try
			{
				Connection con = connection;
				return dlg(con);
			}
			catch (Exception ex)
			{
				error("Database error: ", ex.toString);
				if (m_con)
					m_con.close();
				m_con = null;
				Connection con = connection;
				return dlg(con);
			}
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
		return wrapInRetry(&func);
	}

	void insertPlayer(string login, string password)
	{
		void func(Connection con)
		{
			con.exec("INSERT INTO players (login_name, login_password) " ~
				"VALUES(?, ?)", login, password);
		}
		wrapInRetry(&func);
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
		wrapInRetry(&func);
	}
}