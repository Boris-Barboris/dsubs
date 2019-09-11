module dsubs_server.connections.database;

import core.thread;

import std.array: array;

import mysql;

import dsubs_server.common;


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
}