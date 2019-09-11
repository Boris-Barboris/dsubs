Migrating to v2.0.0
===================

As of v2.0.0, mysql-native has undergone a small redesign of its
[Prepared](http://semitwist.com/mysql-native/mysql/prepared/Prepared.html)
struct for prepared statements. Along with some other improvements,
mysql-native's prepared statements are now connection-independent and
work better with connection pools. See the motivation and exact details
of the change in
[ABOUT_PREPARED_V2.md](https://github.com/mysql-d/mysql-native/blob/master/ABOUT_PREPARED_V2.md).

Unfortunately, these improvements have necessitated some breaking
changes to the API for the
[Prepared](http://semitwist.com/mysql-native/mysql/prepared/Prepared.html)
struct. Any code which uses prepared statements will need some small updates.

The changes needed in your code are simple syntactical changes. Before,
in v1.x.x, you would call the exec/query functions on your Prepared
instance. Now, you will instead use overloads of
[the regular exec/query funtions](http://semitwist.com/mysql-native-docs/v1.2.0/mysql/commands.html),
passing your Prepared instance in place of a raw SQL string.

Specifically, any instances in your code of the following:

```d
preparedStatement.exec()
preparedStatement.query()
preparedStatement.queryRow()
preparedStatement.queryRowTuple(outputArgs...)
preparedStatement.queryValue()
preparedStatement.release()
```

Should be changed to:

```d
connection.exec(preparedStatement)
connection.query(preparedStatement)
connection.queryRow(preparedStatement)
connection.queryRowTuple(preparedStatement, outputArgs...)
connection.queryValue(preparedStatement)
connection.release(preparedStatement)
```

This change is needed because now, once a prepared statement has been created
on a connection, a Prepared no longer keeps track of which connection created
it. In fact, it is no longer tied to any specific connection at all, and can
safely be used on any connection. Behind the scenes, mysql-native automatically
handles all the details necessary to make this work. If you wish to know
exactly how this is done, see
[ABOUT_PREPARED_V2.md](https://github.com/mysql-d/mysql-native/blob/master/ABOUT_PREPARED_V2.md).

Also, note that the `prepare()` function has moved from `mysql.prepared` to
`mysql.connection` as it is specific to `mysql.connection.Connection`, and
this helps keep `mysql.prepared` completely non-dependent on `mysql.connection`.

Since these changes may become tedious and time-consuming, and your project
may have other pressing priorities, mysql-native offers a *temporary*
backwards-compatibility tool which may be of some help:

Simply change any instance of `prepare(...)` to `prepareBackwardCompat(...)`
(note, this will return a [`BackwardCompatPrepared`](#####)
instead of a
[`Prepared`](http://semitwist.com/mysql-native/mysql/prepared/Prepared.html)),
and your prepared statement will be wrapped in an "alias this"-based type
supporting both the new and old syntax until you have a chance to fully update
your code. See
[`BackwardCompatPrepared`](#####) for more info.

Be aware there are downsides to using `prepareBackwardCompat`: You loose
certain safety and vibe.d forward-compatibility benefits of the newly improved
`Prepared`, it doesn't support `ColumnSpecialization, `prepareFunction`,
`prepareProcedure`,
the old API for `release`, or any of the exec/query overloads that automatically take
prepared statement arguments. Also, you will face an onslaught of deprecation
messages helpfully reminding you how to update your code. So be sure to only
use `prepareBackwardCompat` as a temporary measure, and complete the migration
properly at your earliest convenience.
