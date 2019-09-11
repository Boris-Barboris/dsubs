(This document is an updated version of what was originally
written in Issue [#95](https://github.com/mysql-d/mysql-native/issues/95).)

Redesigning Prepared for v2.0.0
===============================

Current downsides (v1.x.x):
---------------------------

Current design of prepared statements (while a vast improvement over the
pre-v1.0.0 `struct Command`-based interface, IMHO), has a few downsides:

1. They don't play well with connection pools
([see here](https://github.com/mysql-d/mysql-native/issues/87#issuecomment-259484192))
because they are tied to a particular connection (which is inherent to the way
the MySQL client/server protocol works).

2. When using vibe.d, they cannot be used across fibers or after a
LockedConnection is released, or bad things may happen (again, because they
are inherently tied to a connection, as per the communications protocol).
See #97. I suspect this might also be the root of #153 (though I'm uncertain).

3. They expose a duplicate exec/query interface that mirrors that of
Connection. Not the most DRY, and leads to some awkwardness in the docs, IMO.

4. Every instance of `Prepared` has *both* `exec` functions (for SELECT/etc)
and `query...` functions (for INSERT/UPDATE/etc). But the SQL is already chosen
at construction, so no `Prepared` will *ever* be able to use both `exec` and
`query...`: For every `Prepared`, either `exec` is *never* valid or `query...`
is *never* valid. This always stuck me as messy and uncomfortable.

5. `Prepared` vs `PreparedImpl`: This situation is a bit messy, too. The real
implementation *and* API of prepared statements is in `PreparedImpl`.
`Prepared` is just a refcounted wrapper overtop that makes a mess of the
ddox-generated documentation, AND no longer accomplishes anything *anyway*
now that `PreparedImpl` no longer has any dtor (for various complicated
reasons relating to struct dtors, the auto-purge feature from v1.1.4 and
recognizing that manual release of statements from the server isn't strictly
necessary, being per-connection after all).

6. Mysql-native is not currently templated on connection type, it uses a literal
`Connection` throughout. Unfortunately, this means the `LockedConnection!Connection`
returned by Vibe.d's connection pools (which `MySQLPool` is based on) gets
downgraded to a mere `Connection`. Ordinarily this would be fine if it was only
ever passed along, but `Prepared` currently stores a reference to a
`Connection`,
[thus defeating LockedConnection's refcounting safety](http://forum.rejectedsoftware.com/groups/rejectedsoftware.vibed/thread/48837/).
Plus, if a Vibe.d update addresses this, then mysql-native will likely need
to correct this just to still compile anyway.

Why these problems?
-------------------

I think, for the most part, these issues are ultimately symptomatic of the
Prepared abstraction not accurately matching the reality. Thus, it needs
high-level rethinking:

Currently, `Prepared` (just like the original functionality in the old
pre-v1.0.0 `Command` struct) is designed around the low-level reality that
MySQL ties prepared statements to individual connections. But then, instead
of treating prepared statements as something owned by a connection (as they
realistically are), `Prepared` flips this around and *has a* connection
instead.

It's also wrong on a higher level: Conceptually, to a database's human user,
a prepared statement is...an SQL statement...that just has special "slots"
for parameters and provides certain benefits. To a user, that's it, nothing
more. That these particular statements happen to be tied to individual
connections is merely an implementation detail of the communications protocol. 

I believe these disconnects are the major cause of the above problems with `Prepared`.

Solution for v2.0.0:
--------------------

Originally, I was thinking about (if anything *at all*) *maybe* offering an
additional abstraction over top `Prepared` which manages prepared statements
across multiple connections. But that would only address the first problem
above, not all of them, and I now believe would likely create additional
mess and problems due to the original disconnect only being covered up,
not resolved.

So I think a redesign is warranted:

- Get rid of `PreparedImpl`. Just have a `Prepared` struct and be done with it.
In the unlikely case anyone really does need deterministic server-side release
of prepared statements, they can just make a trivial RefCounted wrapper over
`Prepared` (as they would need to do since v1.1.4 anyway): Make an alias this
object wrapping `Prepared`. Call `Prepared.release` in the dtor. Wrap it in
RefCounted!T. Done.

- Get rid of `Prepared`'s reference to a connection, as well as all of
`Prepared`'s exec/query functions. To execute a prepared statement, instead
of calling exec/query on a Prepared, you'd pass a Prepared in place of an SQL
string to an overload of `Connection.exec` or `Connection.query...`.

- Since the reality is that "a connection HAS a prepared statement" and
"prepared statements are a *feature of* a connection", not the other way
around, each Connection would internally manage its own set of prepared
statements, indexed by some the SQL string itself. If the user tries to use
a statement that hasn't been prepared on this connection, the connection
automatically creates it.

- `struct Prepared` itself shouldn't have any "release" or "register"
functionality of its own, at all. That should be fully considered a
charactaristic of the communications channel, not a characteristic of
statements.

- `Connection` should have a `.release(Prepared)` to manually release a
prepared statement from an individual connection. It'll safely do nothing if
the statement hasn't been registered on the connection, or has already been
released (as defined by the statement's SQL string).

- Any functionality to manually release a Prepared from ALL connections
should be in `MySQLPool`. This will not be in v2.0.0 though,
it is delayed until v2.1.0 or so.

- Connection and MySQLPool should also have `.register(Prepared)`
(or is there a better name?) to manually create a prepared statement on a
connection, for when the user prefers an eager setup of Prepared over lazy
as-needed setup. If register is NOT called manually, then a prepared statement
will be still be automatically registered when its actually used.

- When a statement is manually registered on a MySQLPool (as opposed to
a Connection), The MySQLPool will manually register it on all
currently-open connections. After this point, the statement will automatically
be registered on all new connections, immediately upon each new connection's
creation, until `MySQLPool.release` is called on the statement. This will also
not be in v2.0.0 though, it is delayed until v2.1.0 or so.

- In the future, other functionality could be added:
`Connection/MySQLPool.releaseAllPrepared`, `Connection/MySQLPool.releaseStalePrepared`,
`bool Connection/MySQLPool.autoReleaseStalePrepared`, etc.

- To clarify: From the perspective of a Connection, the uniqueness or identity
of a prepared statement is to be defined by the statement's SQL string,
not by the whole Prepared object (which wouldn't be realistic anyway, since
Prepared is a struct, not a class).

- Creating a prepared statement will still require *using* a Connection,
due to some low-level details (ie: a Prepared needs to know how many args it
takes, but without parsing SQL syntax on our own, that info, as well as some
other info Prepared uses, needs to come from the server.) However, once
created, the Prepared will no longer hold any reference, or any other
ties, to any one particular Connection.

- `prepare()` will move from `mysql.prepared` to `mysql.connection` since
it relies on `Connection`. This will eliminate `mysql.prepared`'s dependency
on `mysql.connection`.

- Any runtime instance of `Prepare` will be not only be connection-independent,
but could (in theory) even be applied to completely different types of
transports having nothing to do with `mysql.connection` at all.

- Deprecate `MYXNotPrepared`: It will no longer need be thrown.

I think that neatly addresses all of the problems above.

Does all this mean mysql-native is getting too high-level for its charter?
--------------------------------------------------------------------------

Mysql-native was originally intended as a low-level client lib on which
higher-level DB libs, ORMs, etc, could be based. There *is* need for and
value in that.

It could be argued that mysql-native is, in some ways, higher level than
that original charter, and the same could be said for some of these changes.
However, I don't think these changes make it too high-level for the vast
majority of use-cases, and I do believe these higher-level interfaces are
more than worthwhile and moving in a very good direction for the average D
database user.

So what of the need for a stripped-down low-level API?
------------------------------------------------------

First of all, there's nothing stopping other high-level DB libs from basing
their MySQL/MariaDB support on top of mysql-native's higher-level interfaces.
That's entirely viable, and may even make things easier for the lib developers.
And mysql-native *does* intend to reduce any overhead it does have and keep
that to a minimum, even for high-level functionality (IMO, that's part of D's
own charter, after all).

But aside from that: For the sake of sensible code hygiene and maintainability,
my intention for the near-term future of this library is to clean up the
internal design and separate all the low-level communications code out of the
higher-level interfaces. This will have the additional benefit of opening the
door for *further* cleanup of the internal API, which will then become a new,
optional, low-level API - once which I think should work better than the old
original pre-v1.0.0 design (which arguably had somewhat of a high/low-level
identity crisis and the API had various dark dangerous corners because of
that). In long-term, I'm hoping that will also open up the door for additional
DB backends, such as Postgres.
