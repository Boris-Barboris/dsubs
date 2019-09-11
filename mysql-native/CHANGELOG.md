v2.3.0 - 2019-02-23
=====================

- **New:** [#188](https://github.com/mysql-d/mysql-native/issues/188):
	Expose column names in Row struct via `Row.getName(index)`. (@jpf91)
- **Tests:** [#186](https://github.com/mysql-d/mysql-native/issues/186):
	Fix metadata tests on MariaDB 10.2 and 10.3
- **Tests:** Rework travis config and scripts, including:
	- General cleanup.
	- Convert test scripts from bash/batch to D.
	- Testing on more versions of MariaDB server.
	- [#173](https://github.com/mysql-d/mysql-native/issues/173):
		Support for per-job `dub.selections.json` overrides (needed for testing on DMD 2.079+).
	- [#184](https://github.com/mysql-d/mysql-native/issues/184):
		Speed up full Phobos+Vibe testing by skipping redundant tests between
		both Phobos and Vibe builds.

v2.2.2 - 2018-05-03
=====================

Minor updates.

- **Fixed:** [#177](https://github.com/mysql-d/mysql-native/issues/177):
	Update unit-threaded, and don't lock mysql-native to a specific version
	of unit-threaded. (@ghost91)
- **Fixed:** [#178](https://github.com/mysql-d/mysql-native/issues/178),
	[#179](https://github.com/mysql-d/mysql-native/issues/179):
	Fix deprecation message in DMD v2.080.0: Replace enforceEx by enforce (@ghost91)

v2.2.1 - 2018-03-09
=====================

Bugfixes.

- **Fixed:** [#170](https://github.com/mysql-d/mysql-native/issues/170):
	Assertion when concurrently using multiple LockedConnection. (@s-ludwig, @Abscissa)
- **Fixed:** `MySQLPool.lockedConnection` returns `Connection` instead
	of the intended `LockedConnection!Connection` as per the spec. (@s-ludwig)
- **Fixed:** Assert failure on closed connections on `vibe-core` (used by
	default in vibe.d as of vibe.d v0.8.3). (@Abscissa)
- **Fixed:** Program crash upon auto-purge on a closed connection when using
	`vibe-core` (used by default in vibe.d as of vibe.d v0.8.3). (@Abscissa)
- **Tests:** [#163](https://github.com/mysql-d/mysql-native/issues/163):
	Travis should treat sporadic dub outages as a "job error" not
	"tests failed" (@Abscissa)

v2.2.0 - 2018-03-03
=====================

Maintenance release.

- **Fixed:** [#165](https://github.com/mysql-d/mysql-native/issues/165):
	MySQLPool should automatically reopen any closed connections.
	(Not as big of a deal as it sounds because closed connections
	automatically reconnect upon use anyway. This just makes it eager
	instead of lazy and ensures there's no confusion from the pool handing
	out a "closed" connection.) (@Abscissa)
- **Fixed:** [#167](https://github.com/mysql-d/mysql-native/issues/167):
	ResultRange doesn't get invalidated upon reconnect. (@Abscissa)
- **Fixed:** Remove unnecessary precondition that connection must be
	closed before calling `Connection.connect`. (@Abscissa)
- **Fixed:** [#121](https://github.com/mysql-d/mysql-native/issues/121):
	Use `const(char[])` instead of `string` for queries. (@Abscissa)
- **Fixed:** [#13](https://github.com/mysql-d/mysql-native/issues/13):
	No support for type modifiers in prepared statement parameters. (@Abscissa)
- **Tests:** Add tests for reconnecting. (@Abscissa)
- **Internal:** [#144](https://github.com/mysql-d/mysql-native/issues/144):
	Move all packet handling, etc., into mysql.protocol.comms (@Abscissa)

v2.1.0 - 2018-03-02
=====================

New prepared statement features.

Since v2.1.0-rc2:
- **Fixed:** [#28](https://github.com/mysql-d/mysql-native/issues/28):
	MYXProtocol thrown when using large integers as prepared parameters. (@Abscissa)

Since v2.1.0-rc1:
- **Docs:** Update readme example for new simplified prepared statement interface. (@Abscissa)

Since v2.0.0:
- **New:** [#118](https://github.com/mysql-d/mysql-native/issues/118):
	Convenience
	[exec/query overloads](http://semitwist.com/mysql-native/mysql/commands.html)
	that do parameterized SQL. (@Abscissa)
- **New:** [#162](https://github.com/mysql-d/mysql-native/issues/162):
	Create
	[Connection.releaseAll](http://semitwist.com/mysql-native/mysql/connection/Connection.releaseAll.html)
	(@Abscissa)
- **New:**
	Add a
	[Connection.register](http://semitwist.com/mysql-native/mysql/connection/Connection.register.html)
	overload that takes an sql string, for symmetry with
	[Connection.release](http://semitwist.com/mysql-native/mysql/connection/Connection.release.html)
	(@Abscissa)
- **New:** [#160](https://github.com/mysql-d/mysql-native/issues/160):
	Pool-level prepared statement management tools for
	[MySQLPool](http://semitwist.com/mysql-native/mysql/pool/MySQLPool.html),
	including `autoRegister`/`autoRelease`/etc...
	(@Abscissa)
- **Tests:** [#149](https://github.com/mysql-d/mysql-native/issues/149):
	Optionally support [unit-threaded](https://github.com/atilaneves/unit-threaded)
	for vibe tests (not used by default) (@Abscissa)
- **Tests:** [#161](https://github.com/mysql-d/mysql-native/issues/161):
	Added tests for ParameterSpecialization (ie, chunked transfer). (@Abscissa)

v2.0.0 - 2018-02-13
=====================

Connection-independent redesign of Prepared, plus other new features and housekeeping.
See the [migration guide](https://github.com/mysql-d/mysql-native/blob/master/MIGRATING_TO_V2.md).

Since v2.0.0-rc2:
- **Fixed:** ParameterSpecialization chunked transfer fails unless
	the total size is a multiple of the chunk size. (@Abscissa)
- **Docs:** Improve documentation relating to chunked transfer. (@Abscissa)

Since v2.0.0-rc1:
- **Change:** The query functions which take prepared statements no longer
	support `ColumnSpecialization`. Use `Prepared.columnSpecials` instead. (@Abscissa)
- **New:** Added `Prepared.columnSpecials` to get/set the array of `ColumnSpecialization`. (@Abscissa)
- **Docs:** More CSS improvements. (@Abscissa)

Since v1.2.2:
- **Change:** [#95](https://github.com/mysql-d/mysql-native/issues/95),
	[#97](https://github.com/mysql-d/mysql-native/issues/97),
	[#157](https://github.com/mysql-d/mysql-native/issues/157):
	Redesigned Prepared to be connection-independent, support auto-registration
	and fix a few problems. For details, see
	[ABOUT_PREPARED_V2.md](https://github.com/mysql-d/mysql-native/blob/master/ABOUT_PREPARED_V2.md)
	(@Abscissa)
- **Change:** `prepare`, `prepareFunction` and `prepareProcedure` have moved
	from `mysql.prepared` to `mysql.connection`. This is because they are
	specific to `Connection`, and the new `Prepared` design (and thus
	`mysql.prepared`) is completely non-dependent on `Connection`.
- **New:** [#115](https://github.com/mysql-d/mysql-native/issues/115):
	Added Prepared.lastInsertID to retrieve last ID inserted by the given
	prepared statement. (@Abscissa)
- **New:** [#147](https://github.com/mysql-d/mysql-native/issues/147):
	Pools can take optional callback for when new connections are created (@Abscissa)
- **Removed:** Re-removed all deprecated symbols that were removed in v1.2.0 (@Abscissa)
- **Removed:** Removed additional deprecated symbols: (@Abscissa)
	- MySQL[whatever]Exception: Use `MYX[whatever]` instead.
	- querySet/ResultSet: Import std.array and use `query(...).array` to
		receive `Row[]` instead of a ResultSet.
	- MYXDataPending: No longer thrown by mysql-native, as of v1.1.4. You can
		safely remove all MYXDataPending handling from your code.
- **Removed:** Removed long-outdated Vibe.d `EventedObject` interface from `Connection`.
	That is: `acquire()`, `release()`, `isOwner()` and `amOwner()` (@Abscissa)
- **Removed:** [#96](https://github.com/mysql-d/mysql-native/issues/96):
	Removed public access to `Connection.getNextRow`, which was
	intended as internal, and has been documented as such for awhile now. (@Abscissa)
- **Deprecated:** `MYXNotPrepared`: The new prepared statement design
	eliminates the need for this exception which is no longer thrown. (@Abscissa)
- **Docs:** [#146](https://github.com/mysql-d/mysql-native/issues/146):
	Make sure all ddox cross-linking is fixed. (@Abscissa)
- **Docs:** [#158](https://github.com/mysql-d/mysql-native/issues/158):
	Fixed images missing in sidebar, and updated DDOX styles/scripts (@Abscissa)
- **Internal:**
	Renamed debug symbol `MYSQL_INTEGRATION_TESTS` to the more accurate
	`MYSQLN_TESTS`. (@Abscissa)

v1.2.2 - 2018-01-27
=====================

Bugfix

- **Fixed:** [#154](https://github.com/mysql-d/mysql-native/issues/154),
	[#155](https://github.com/mysql-d/mysql-native/issues/155):
	Connection becomes unusable when mysql server closes socket. (@schveiguy)

v1.2.1 - 2018-01-13
=====================

Fix semver mistake by re-adding deleted symbols.

- **Fixed:** [Semver](https://semver.org/) Requires ALL breaking changes to bump
  the MAJOR version number, never just the MINOR. Fixed this by re-adding the
  old deprecated symbols which were deleted in the previous release. They will
  be removed again in the next release, v2.0.0.

v1.2.0 - 2017-12-15
=====================

Housekeeping: Deprecations, cleanup and doc improvements.

- **Fixed:** Glaring mistakes in the example from `README` and `example.d`. (@Abscissa)
- **Fixed:** [#133](https://github.com/mysql-d/mysql-native/issues/133):
	Sometimes null is incorrectly indicated by Variant containing `void` rather
	than `null` as intended. (@Marenz)
- **Fixed:** [#152](https://github.com/mysql-d/mysql-native/issues/152):
	Exception when sending Timestamp in prepared statement. (@Abscissa)
- **Removed:** Removed deprecated symbols: (@Abscissa)
	- queryResult: Use querySet instead.
	- querySequence: Use query instead.
	- queryTuple: Use queryRowTuple instead.
	- struct Command: This is obsolete pre-v1.0.0 interface. Use the functions
		in mysql.commands and mysql.prepared instead.
	- mysql.db: Use mysql.pool instead.
	- MysqlDB: Use  mysql.pool.MySQLPool instead.
	- struct DBValue: Use std.variant.Variant instead.
	- ResultSequence: Use ResultRange instead.
- **Deprecated:** Newly deprecated symbols: (@Abscissa)
	- [#145](https://github.com/mysql-d/mysql-native/issues/145):
		MySQL[whatever]Exception: Use `MYX[whatever]` instead.
	- [#126](https://github.com/mysql-d/mysql-native/issues/126):
		querySet/ResultSet: Import std.array and use `query(...).array` to
		receive `Row[]` instead of a ResultSet.
	- MYXDataPending: No longer thrown by mysql-native, as of v1.1.4. You can
		safely remove all MYXDataPending handling from your code.
- **Docs:** API documentation now displays the lib version and permalinks to
	the homepages of the project, the current API docs, the latest API docs
	and the list of api docs for previous versions. (@Abscissa)
- **Docs:** Various documentation updates. (@Abscissa)
- **Docs:** [#128](https://github.com/mysql-d/mysql-native/issues/128):
	Show connection string format in readme example. (@Abscissa)
- **Docs:** [#136](https://github.com/mysql-d/mysql-native/issues/136):
	Document D <-> MySQL type mappings. (@Abscissa)
- **Tests:** Include `example.d` in tests. (@Abscissa)
- **Tests:** Fixed deprecation messages when compiling tests. (@Abscissa)
- **Tests:** [#140](https://github.com/mysql-d/mysql-native/issues/140):
	Add a travis job to test after a `dub upgrade`. (@SingingBush)

v1.1.4 - 2017-12-04
=====================

Introduced auto-purge to fix a few problems.

- **Fixed:**
	[#117](https://github.com/mysql-d/mysql-native/issues/117):
	ResultRange cannot be copied. (@Abscissa)
- **Fixed:**
	[#119](https://github.com/mysql-d/mysql-native/issues/119):
	Is a defensive `Connection.purgeResult` call necessary before executing another statement?
	(As of this release, the answer changed from "sometimes" to "no") (@Abscissa)
- **Fixed:**
	[#139](https://github.com/mysql-d/mysql-native/issues/139):
	Server packet out of order when Prepared is destroyed too early. (@Abscissa)
- **Change:**
	MySQLDataPendingException (aka, MYXDataPending) is no longer necessary,
	and no longer thrown. When issuing a command that communicates with the
	server while a ResultRange still has data pending, instead of throwing,
	mysql-native now automatically purges the range and safely marks it as
	invalid and no longer usable. This was changed in order to fix #117, #119,
	and #139. This change should neither break user code nor require
	any changes. (@Abscissa)
- **Change:**
	Manually releasing a prepared statement is no longer guaranteed to notify
	the server immediately. In order to facilitate the above fixes, and avoid
	any nasty surprise with struct dtors triggering results purges implicitly,
	any release of prepared statements from the server is now queued until
	mysql-native can be certain no data is already pending. This change should
	neither break user code nor require any changes. (@Abscissa)
- **Change:**
	Prepared statements are no longer released automatically, due to the fix
	for #117. However, prepared statements and their lifetimes are tied to
	individual connections, and thus will die along with their connection,
	so manual release is not strictly necessary either. Accordingly, this
	change should neither break user code nor require any changes. (@Abscissa)
- **Fixed:**
	[#143](https://github.com/mysql-d/mysql-native/issues/143):
	Keep travis-ci build times under control by limiting the number of
	compiler versions tested on OSX. (@SingingBush)

v1.1.3 - 2017-12-02
=====================

- **Fixed:**
	[#138](https://github.com/mysql-d/mysql-native/issues/138):
	Prepared: Prevent mem allocs during cleanup. (@Marenz)
- **Fixed:**
	[#135](https://github.com/mysql-d/mysql-native/issues/135):
	Now works on DMD 2.076 and up. (@SingingBush)
- **New:**
	[#135](https://github.com/mysql-d/mysql-native/issues/135):
	Add travis-ci testing for OSX. (@SingingBush)
- **Fixed:**
	DMD 2.074.x gives compile error when building tests. (@Abscissa)

v1.1.2 - 2017-09-20
=====================

- **Fixed:**
	[#130](https://github.com/mysql-d/mysql-native/issues/130):
	Compilation error when compiling in singleFile mode. (@Marenz)

v1.1.1 - 2017-09-20
=====================

- **Fixed:**
	[#116](https://github.com/mysql-d/mysql-native/issues/116):
	Prevent segfault on copying ResultRange. (@schveiguy)
- **Fixed:**
	[#120](https://github.com/mysql-d/mysql-native/issues/120):
	Fix typos / grammars in documentation (@Marenz)
- **Fixed:**
	[#124](https://github.com/mysql-d/mysql-native/issues/124):
	Fix deprecations: Change deprecated std.string.munch to std.algorithm.skipOver. (@Kozzi11)

v1.1.0 - 2017-06-08
=====================

- **Fixed:**
	[#99](https://github.com/mysql-d/mysql-native/issues/99):
	Update dub.sdl to allow vibe-d 0.8.* releases.
- **Fixed:**
	[#111](https://github.com/mysql-d/mysql-native/issues/111):
	NEWDECIMAL type returns the wrong value. Since this type is intended as arbitrary
	precision, the server itself sends it as a string. In order to avoid unexpected
	loss of precision, mysql-native does not attempt to convert the string to a
	floating-point type. If conversion to floating point is required, users can simply
	pass the string to Phobos's `to!real` themselves.

v1.0.0 - 2017-02-26
=====================
- **Summary:**
	API overhauled for better safety, reliability and ease-of-use. Deprecated and
	replaced entire Command struct with better design. Better handling of null.
	Improved/expanded docs. Various bugs fixed. More rigorous test suite.
- **New:**
	[#85](https://github.com/mysql-d/mysql-native/issues/85):
	Redesigned SQL-based functions. Use the various `query` functions for
	SELECT-like commands (to receive a result set), or the `exec` function for
	non-SELECT commands to receive "rows affected".
- **New:**
	New modules for better organization of features:
	- **New:**
		Module `mysql.prepared`: Home of the newly redesigned prepared statement
		functionality.
	- **Change:**
		Module `mysql.exceptions`: Contains all exceptions defined by mysql-native.
	- **Change:**
		Module `mysql.metadata`: Metadata-related symbols formerly from
		`mysql.protocol.extra_types`.
	- **Change:**
		Module `mysql.types`: Structures for MySQL types not built-in to D/Phobos,
		formerly from `mysql.protocol.extra_types`.
- **New:**
	Prepared statement improvements, including much improved support for null.
	- **New:**
		`Prepared` struct to represent a prepared statement.
	- **New:**
		Prepared statements support setting arguments directly to `null` or `Nullable!T`.
		Using `setNullArg` (formerly `setNullParam`) is no longer necessary (but still supported).
	- **Change:**
		`Row.opIndex` no longer throws if the value is null. Instead, it returns `Variant(null)`.
	- **Change:**
		[#89](https://github.com/mysql-d/mysql-native/issues/89):
		Values bound to prepared statement parameters are now taken by value, not by
		reference (but only when using the new `Prepared` struct, not the
		now-deprecated `Command` struct).
	- **Fixed:**
		[#76](https://github.com/mysql-d/mysql-native/issues/76):
		Prepared statements are auto-released when their reference count reaches zero.
- **New:**
	Various new subclasses of `MySQLException` added, for better fine-grained control.
- **New:**
	`Row` struct now supports `length` property and `opDollar`.
- **New:**
	[#74](https://github.com/mysql-d/mysql-native/issues/74):
	`mysql.pool.MySQLPool` (formerly `mysql.db.MysqlDB`) now supports vibe.d's
	`ConnectionPool.maxConcurrency` feature.
- **Change:**
	Drop support for DMDFE 2.067.x and below. Compiles on
	DMDFE 2.068.2 through 2.072.1. See [.travis.yml](https://github.com/mysql-d/mysql-native/blob/master/.travis.yml)
	for full list of supported compilers.
- **Change:**
	[#86](https://github.com/mysql-d/mysql-native/issues/86),
	[#87](https://github.com/mysql-d/mysql-native/issues/87):
	`Command` struct is now deprecated. Its functionality
	has been split and moved (as appropriate) into Connection, various
	free-functions, and a new reference-counted `Prepared` struct exclusively
	for prepared statements.
- **Change:**
	Renamed `mysql.db.MysqlDB` (misleading. confusing name) to `mysql.pool.MySQLPool`.
- **Change:**
	Module `mysql.connection` no longer acts as a package.d, publicly importing
	other modules. To import all of mysql-native, use `import mysql;`.
- **Change:**
	`ResultSet.asAA` and `ResultRange.asAA` now return Variant[string] instead
	of DBValue[string]. DBValue is no longer needed and now deprecated (as it
	was only used by `asAA` and Variant now handles null properly.)
- **Change:**
	Improved separation between internal (`mysql.protocol`) and external interfaces.
	- **Change:**
		No longer publicly imports internal-only symbols by default.
	- **Change:**
		Renamed module `mysql.protocol.commands` to `mysql.commands`.
	- **Change:**
		Moved `ParameterSpecialization` into `mysql.prepared` (was in `mysql.protocol.extra_types`).
	- **Change:**
		Moved `ColumnSpecialization` into `mysql.commands` (was in `mysql.protocol.extra_types`).
	- **Change:**
		Moved the other public-API members of `mysql.protocol.extra_types` into
		new modules `mysql.metadata` and `mysql.types`.
	- **Change:**
		Removed module `mysql.common`: Its contents have been moved into
		`mysql.exceptions` and `mysql.protocol.sockets`.
- **Fixed:**
	[#75](https://github.com/mysql-d/mysql-native/issues/75),
	[#89](https://github.com/mysql-d/mysql-native/issues/89):
	Fixed problems where various structs and user data was unsafe to move/copy
	due to usage of internal pointers/references. Such usages of internal
	pointers/references have been eliminated.
- **Fixed:**
	Better safety against new commands being issued before an earlier command is complete.
- **Fixed:**
	Reliability: Now get an MySQLInvalidatedRangeException instead of undefined
	behavior when using a ResultSequence after it's been invalidated by either
	a new command being issued or the results being purged.
- **Fixed:** Many documentation improvements and fixes.
- **Fixed:** More unittests.

v0.1.7 - 2016-10-20
=====================
- **New:**
	Test suite automatically tests with both Vibe and Phobos sockets,
	not just Phobos. (@Abscissa)
- **Change:**
	Drop support for DMDFE 2.066.1 and below. Compiles on
	DMDFE 2.067.1 through 2.072.0. See [.travis.yml](https://github.com/mysql-d/mysql-native/blob/master/.travis.yml)
	for full list of supported compilers.
- **Fixed:** Fix an import deprecation message for DMD 2.071. (@Abscissa)
- **Fixed:**
	[#57](https://github.com/mysql-d/mysql-native/pull/57):
	Added support for passing null parameters in prepared statements by using Variant(null) (@machindertech)
- **Fixed:**
	[#63](https://github.com/mysql-d/mysql-native/issues/63)/[#69](https://github.com/mysql-d/mysql-native/pull/69):
	Add escape module to package import (@Marenz)
- **Fixed:**
	[#68](https://github.com/mysql-d/mysql-native/pull/68):
	Update alias syntax (@Marenz)

v0.1.6 - 2016-09-08
=====================
- **Change:** If not using dub, vibe.d support is now enabled with -version=Have_vibe_d_core, not -version=Have_vibe_d (@Abscissa)
- **Fixed:** Linker error when using dub to import *just* vibe-d:core, but not all of vibe.d. (@Abscissa)
- **Fixed:** Use 'dub.json', not outdated 'package.json' name. (@Abscissa)

v0.1.5 - 2016-09-08
=====================
- **New:** [#73](https://github.com/mysql-d/mysql-native/issues/73): [Integration testing](https://travis-ci.org/mysql-d/mysql-native) via [travis-ci](https://travis-ci.org/). (@Abscissa)
- **New:** Started this changelog. (@Abscissa)
- **Fixed:** [#20](https://github.com/mysql-d/mysql-native/issues/20): Contract failure in consume!string (@Marenz)
- **Fixed:** [#50](https://github.com/mysql-d/mysql-native/issues/50): bindParameters example was wrong (@Abscissa)
- **Fixed:** [#67](https://github.com/mysql-d/mysql-native/issues/67): Fix unittest for escape (@Marenz)
- **Fixed:** [#70](https://github.com/mysql-d/mysql-native/issues/70): Check for errors where we expect the greeting packet (@Marenz)
- **Fixed:** [#78](https://github.com/mysql-d/mysql-native/issues/78): Use vibe-d sub package dependency and a more current version (@s-ludwig)
- **Fixed:** [#79](https://github.com/mysql-d/mysql-native/issues/79): Dub fetch all vibe-d dependencies, even if there is no reason (@s-ludwig)

v0.1.4 - 2016-04-08
=====================
- **New:** Add script to automatically compile/run the tests. (@Abscissa)
- **Fixed:** [#61](https://github.com/mysql-d/mysql-native/issues/61): Add escape functions (@Marenz)
- **Fixed:** [#62](https://github.com/mysql-d/mysql-native/issues/62): Documentation typo (@eco)
- **Fixed:** [#66](https://github.com/mysql-d/mysql-native/issues/66): Can't connect when omitting default database (@Abscissa)

v0.1.3 - 2015-08-08
=====================
- **New:** [#60](https://github.com/mysql-d/mysql-native/issues/60): Add 'execSQL' overload for when you don't care about "rows affected". (@Abscissa)

v0.1.2 - 2015-03-31
=====================
- **Fixed:** [#55](https://github.com/mysql-d/mysql-native/issues/55): Replace string with const(char)[] for sql string (@mathias-baumann-sociomantic)
- **Fixed:** [#56](https://github.com/mysql-d/mysql-native/issues/56): Result set quantity does not equal MySQL rows quantity (@Abscissa)

v0.1.1 - 2015-01-24
=====================
- **Fixed:** Wrong number of bytes read (@sshamov)

v0.1.0 - 2014-10-05
=====================
- **Fixed:** Test don't compile on DMD 2.064.2 (@Abscissa)
- **Fixed:** [#24](https://github.com/mysql-d/mysql-native/issues/24): BIT type handled incorrectly (@Abscissa)
- **Fixed:** [#33](https://github.com/mysql-d/mysql-native/issues/33): "*TEXT" types treated as ubyte[], not string (@Abscissa)
- **Fixed:** [#42](https://github.com/mysql-d/mysql-native/issues/42): Can't login with empty password (@Abscissa)

v0.0.16 - 2014-10-03
=====================
- **Change:** Split into multiple modules.
- **Fixed:** Remove redundant (and outdated) "homepage" field from package.json. (@s-ludwig)
- **Fixed:** [#39](https://github.com/mysql-d/mysql-native/issues/39): Unsupported SQL type NEWDECIMAL (@bhechinger)
- **Fixed:** [#45](https://github.com/mysql-d/mysql-native/issues/45): Retrieving table metadata fails with an exception for certain server versions. (@Abscissa)
- **Fixed:** [#48](https://github.com/mysql-d/mysql-native/issues/48): Unittests don't work on MariaDB 5.5 (@Abscissa)

v0.0.15 - 2014-06-06
=====================
- **New:** Add lots of tests (@Abscissa, @simendsjo)
- **Fixed:** Fix MetaData.columns (@Abscissa)
- **Fixed:** Tightened word wrapping in docs. (We don't have to stick to 80 cols, but let's keep it in the general ballpark. Long lines of text are hard to read.) (@Abscissa)
- **Fixed:** docs: A few function names were out of date. (@Abscissa)
- **Fixed:** [#29](https://github.com/mysql-d/mysql-native/issues/29): Misleading error message when trying to access results via an index (@nomad-software)
- **Fixed:** [#36](https://github.com/mysql-d/mysql-native/issues/36): Add colNames and colNameIndicies to ResultSequence (@MartinNowak)
- **Fixed:** [#37](https://github.com/mysql-d/mysql-native/issues/37): Detect nullable types and call nullify in toStruct (@MartinNowak)
- **Fixed:** [#38](https://github.com/mysql-d/mysql-native/issues/38): Fix empty for ResultSequence (Range wouldn't stop correctly when all rows were fetched) (@MartinNowak)
- **Fixed:** [#40](https://github.com/mysql-d/mysql-native/issues/40): Hangs when receiving a value > 250 bytes. (@Abscissa, @fsw)

v0.0.14 - 2014-04-21
=====================
- **Fixed:** Avoid using deprecated vibe.d symbols. (@s-ludwig)
- **Fixed:** [#30](https://github.com/mysql-d/mysql-native/issues/30): Thrown exceptions leave connections in an undefined state. (@Abscissa)

v0.0.13 - 2014-02-19
=====================
- **New:** [#32](https://github.com/mysql-d/mysql-native/issues/32): Add gitignore (@Geod24)
- **Fixed:** [#26](https://github.com/mysql-d/mysql-native/issues/26): Remove checking _valid (which no longer exists) from execFunction and execTuple (@schancel)
- **Fixed:** [#27](https://github.com/mysql-d/mysql-native/issues/27): Added 2 missing casts reported as errrors by DMD-2.065 head. (@ArjanKn)
- **Fixed:** [#31](https://github.com/mysql-d/mysql-native/issues/31): Error message was not displayed (@Geod24)

v0.0.12 - 2013-11-26
=====================
- **Fixed:** Add vibe.d as an optional dependency so that Have_vibe_d gets defined for separate builds (as for "dub generate visuald"). (@s-ludwig)
- **Fixed:** [#25](https://github.com/mysql-d/mysql-native/issues/25): Fix compiler error for the latest vibe.d master. (@s-ludwig)

v0.0.11 - 2013-11-06
=====================
- **New:** Add opDollar to ResultSet. (@Abscissa)
- **Fixed:** Add license field to DUB json file. (@s-ludwig)
- **Fixed:** Bug with TIMESTAMP that's almost undetectable. (@sshamov)
- **Fixed:** [#19](https://github.com/mysql-d/mysql-native/issues/19): Move towards pure, const and nothrow (@simendsjo)
- **Fixed:** [#21](https://github.com/mysql-d/mysql-native/issues/21): Fix purity of exceptions + enforce for dmd 2.064+ (@simendsjo)

v0.0.10 - 2013-08-24
=====================
- **New:** Add function: Connection.reconnect (@Abscissa)
- **New:** Support using connection string for Vibe.d connection pool. (@Abscissa)
- **New:** For connection strings, port is now optional. (@Abscissa)
- **New:** Test app enhancements: Optional conn string on cmdline, better default connection settings, and compile-time option to use Vibe.d connection pool. (@Abscissa)
- **Fixed:** Commented out: Obsolete enforcing inside execPreparedTuple() (@sshamov)
- **Fixed:** Assertion failure when retrieving a TIMESTAMP (@sshamov)
- **Fixed:** Not release prepared stmt if there is no such one (@sshamov)
- **Fixed:** Fix building with DUB and without vibe.d. (@s-ludwig)
- **Fixed:** RangeError when connecting via connection string. (@Abscissa)
- **Fixed:** 64-bit fixes. (@Abscissa)
- **Fixed:** Phobos has SHA1 since v2.061. Use it instead of this project's version. (@Abscissa)
- **Fixed:** [#10](https://github.com/mysql-d/mysql-native/issues/10): Hangs on certain code (Fix compilation for latest vibe.d master) (@s-ludwig)
- **Fixed:** [#11](https://github.com/mysql-d/mysql-native/issues/11): Compiler warnings (@s-ludwig)
- **Fixed:** [#12](https://github.com/mysql-d/mysql-native/issues/12): Ddoc warning (@Abscissa)
- **Fixed:** [#15](https://github.com/mysql-d/mysql-native/issues/15): Compile error on LDC. (@Abscissa)

v0.0.9 - 2013-05-23
=====================
- **New:** Get field/param information. (@Abscissa)
- **New:** Support null values in prepared statements. (@Abscissa)
- **New:** Support Phobos sockets as optional (but default) alternative to vide.d sockets. (@Abscissa)
- **Fixed:** Removed Connection's dtor. (@Abscissa)
- **Fixed:** Don't bother reopening closed connection just to send QUIT command. (@Abscissa)
- **Fixed:** Compile errors for bindParameter (@Abscissa)
- **Fixed:** Assertion failure when retrieving a TIMESTAMP or an unsigned floating-point/fixed-point type. (@Abscissa)

v0.0.8 - 2013-05-03
=====================
- **Fixed:** Fixed compilation for latest vibe.d/dub/DMD versions. (@s-ludwig)
- **Fixed:** Retrieving NULL from a '*BLOB' or '*TEXT' column handles wrong, and messes up the rest of the reterived data. (@Abscissa)

v0.0.7 - 2013-01-17
=====================
- **New:** Subclassed exception MySQLProtocolException for invalid data is received, violating MySQL's network protocol. (@Abscissa)
- **New:** Subclassed exception MySQLReceivedException for when the server returns an error packet. (@Abscissa)
- **Fixed:** Removed the version entry from package.json - not necessary anymore. (@s-ludwig)
- **Fixed:** consume(T:Date) doesn't consume the bytes it used. (@Abscissa)
- **Fixed:** [#7](https://github.com/mysql-d/mysql-native/issues/7): Internal AssertError: Attempting to fetch the front of an empty array of ubyte (@Abscissa)
- **Fixed:** [#8](https://github.com/mysql-d/mysql-native/issues/8): Fixed Date type handling. (@fearfullymade)

v0.0.6 - 2012-12-07
=====================
- **New:** Auto repair of dead connections (@sshamov)
- **New:** Support for Nullable(T) members in toStruct() (@sshamov)
- **New:** Support for null values in toStruct() (@sshamov)
- **New:** [#4](https://github.com/mysql-d/mysql-native/issues/4): Add optional port and capFlags args to mysql.db.MysqlDB connection pool. (@Abscissa)
- **Fixed:** [#1](https://github.com/mysql-d/mysql-native/issues/1): Fix incorrect error connecting to v4.1.1+ server (@Abscissa)
- **Fixed:** [#2](https://github.com/mysql-d/mysql-native/issues/2), [#5](https://github.com/mysql-d/mysql-native/issues/5): Remove unintended additions to the interface (@Abscissa, @simendsjo)
- **Fixed:** [#3](https://github.com/mysql-d/mysql-native/issues/3): Bug with capability flags (@sshamov)
- **Fixed:** [#6](https://github.com/mysql-d/mysql-native/issues/6): Bugs with fetching VARCHAR/BLOB/TEXT (@sshamov)

v0.0.5 - 2012-10-25
=====================
- **Fixed:** Removing again the empty packet assertion. (@s-ludwig)
- **Fixed:** Second attempt to rewrite parseGreeting - now uses getPacket(), just like any other packet. (@s-ludwig)
- **Fixed:** Removed (now) invalid enforcement. (@s-ludwig)
- **Fixed:** Rewrote the greeting message parsing code to not rely on TCP quirks. (@s-ludwig)
- **Fixed:** Merge simendsjo branch with many misc cleanups (@simendsjo, @JollieRoger)

v0.0.4 - 2012-10-11
=====================
- **Fixed:** Fixed up the test application. (@s-ludwig)

v0.0.3 - 2012-10-11
=====================
- **Fixed:** Fixed compilation on latest vibe.d master. (@s-ludwig)

v0.0.2 - 2012-05-19
=====================
- **Fixed:** JSON syntax error in DUB json file. (@s-ludwig)

v0.0.1 - 2012-05-19
=====================
- **New:** First tagged version (@s-ludwig)
- **Fixed:** Adjusted package.json for the new VPM registry. (@s-ludwig)

pre-v0.0.1 (untagged releases) - 2011-11-07 - 2011-11-10
=========================================================
- **New:** Original releases by @britseye (Steve Teale)
