[![Build Status](https://travis-ci.org/mysql-d/mysql-native.svg)](https://travis-ci.org/mysql-d/mysql-native)

A [Boost-licensed](http://www.boost.org/LICENSE_1_0.txt) native [D](http://dlang.org)
client driver for MySQL and MariaDB.

This package attempts to provide composite objects and methods that will
allow a wide range of common database operations, but be relatively easy to
use. It has no dependencies on GPL header files or libraries, instead communicating
directly with the server via the
[published client/server protocol](http://dev.mysql.com/doc/internals/en/client-server-protocol.html).

This package supports both [Phobos sockets](https://dlang.org/phobos/std_socket.html)
and [Vibe.d](http://vibed.org/) sockets. It will automatically use the correct
type based on whether Vibe.d is used in your project. (If you use
[DUB](http://code.dlang.org/getting_started), this is completely seamless.
Otherwise, you can use `-version=Have_vibe_d_core` to force Vibe.d sockets
instead of Phobos ones.)

See [.travis.yml](https://github.com/mysql-d/mysql-native/blob/master/.travis.yml)
for a list of officially supported D compiler versions.

In this document:
* [API](#api)
* [Basic example](#basic-example)
* [Additional notes](#additional-notes)
* [Developers - How to run the test suite](#developers---how-to-run-the-test-suite)

See also:
* [API Reference](http://semitwist.com/mysql-native)
* [Migrating to v2.0.0](https://github.com/mysql-d/mysql-native/blob/master/MIGRATING_TO_V2.md)

API
---

[API Reference](http://semitwist.com/mysql-native)

The primary interfaces:
- [Connection](http://semitwist.com/mysql-native/mysql/connection/Connection.html): Connection to the server, and querying and setting of server parameters.
- [MySQLPool](http://semitwist.com/mysql-native/mysql/pool.html): Connection pool, for Vibe.d users.
- [exec()](http://semitwist.com/mysql-native/mysql/commands/exec.html): Plain old SQL statement that does NOT return rows (like INSERT/UPDATE/CREATE/etc), returns number of rows affected
- [query()](http://semitwist.com/mysql-native/mysql/commands/query.html): Execute an SQL statement that DOES return rows (ie, SELECT) and handle the rows one at a time, as an input range.
- [queryRow()](http://semitwist.com/mysql-native/mysql/commands/queryRow.html): Execute an SQL statement and get the first row.
- [queryValue()](http://semitwist.com/mysql-native/mysql/commands/queryValue.html): Execute an SQL statement and get the first value in the first row.
- [prepare()](http://semitwist.com/mysql-native/mysql/prepared/prepare.html): Create a prepared statement
- [Prepared](http://semitwist.com/mysql-native/mysql/prepared/PreparedImpl.html): A prepared statement, optionally pass it to the exec/query function in place of an SQL string.
- [Row](http://semitwist.com/mysql-native/mysql/result/Row.html): One "row" of results, used much like an array of Variant.
- [ResultRange](http://semitwist.com/mysql-native/mysql/result/ResultRange.html): An input range of rows. Convert to random access with [std.array.array()](https://dlang.org/phobos/std_array.html#.array).

Also note the [MySQL <-> D type mappings tables](https://semitwist.com/mysql-native/mysql.html)

Basic example
-------------
```d
import std.array : array;
import std.variant;
import mysql;

void main(string[] args)
{
	// Connect
	auto connectionStr = "host=localhost;port=3306;user=yourname;pwd=pass123;db=mysqln_testdb";
	if(args.length > 1)
		connectionStr = args[1];
	Connection conn = new Connection(connectionStr);
	scope(exit) conn.close();

	// Insert
	ulong rowsAffected = conn.exec(
		"INSERT INTO `tablename` (`id`, `name`) VALUES (1, 'Ann'), (2, 'Bob')");

	// Query
	ResultRange range = conn.query("SELECT * FROM `tablename`");
	Row row = range.front;
	Variant id = row[0];
	Variant name = row[1];
	assert(id == 1);
	assert(name == "Ann");

	range.popFront();
	assert(range.front[0] == 2);
	assert(range.front[1] == "Bob");

	// Simplified prepared statements
	ResultRange bobs = conn.query(
		"SELECT * FROM `tablename` WHERE `name`=? OR `name`=?",
		"Bob", "Bobby");
	bobs.close(); // Skip them
	
	Row[] rs = conn.query( // Same SQL as above, but only prepared once and is reused!
		"SELECT * FROM `tablename` WHERE `name`=? OR `name`=?",
		"Bob", "Ann").array; // Get ALL the rows at once
	assert(rs.length == 2);
	assert(rs[0][0] == 1);
	assert(rs[0][1] == "Ann");
	assert(rs[1][0] == 2);
	assert(rs[1][1] == "Bob");

	// Full-featured prepared statements
	Prepared prepared = conn.prepare("SELECT * FROM `tablename` WHERE `name`=? OR `name`=?");
	prepared.setArgs("Bob", "Bobby");
	bobs = conn.query(prepared);
	bobs.close(); // Skip them

	// Nulls
	conn.exec(
		"INSERT INTO `tablename` (`id`, `name`) VALUES (?,?)",
		null, "Cam"); // Can also take Nullable!T
	range = conn.query("SELECT * FROM `tablename` WHERE `name`='Cam'");
	assert( range.front[0].type == typeid(typeof(null)) );
}
```

Additional notes
----------------

This requires MySQL server v4.1.1 or later, or a MariaDB server. Older
versions of MySQL server are obsolete, use known-insecure authentication,
and are not supported by this package.

Normally, MySQL clients connect to a server on the same machine via a Unix
socket on *nix systems, and through a named pipe on Windows. Neither of these
conventions is currently supported. TCP is used for all connections.

For historical reference, see the [old homepage](http://britseyeview.com/software/mysqln/)
for the original release of this project. Note, however, that version has
become out-of-date.

Developers - How to run the test suite
--------------------------------------

This package contains various unittests and integration tests. To run them,
run `run-tests`.

The first time you run `run-tests`, it will automatically create a
file `testConnectionStr.txt` in project's base diretory and then exit.
This file is deliberately not contained in the source repository
because it's specific to your system.

Open the `testConnectionStr.txt` file and verify the connection settings
inside, modifying them as needed, and if necessary, creating a test user and
blank test schema in your MySQL database.

The tests will completely clobber anything inside the db schema provided,
but they will ONLY modify that one db schema. No other schema will be
modified in any way.

After you've configured the connection string, run `run-tests` again
and their tests will be compiled and run, first using Phobos sockets,
then using Vibe sockets.
