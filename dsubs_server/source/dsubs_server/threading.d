module dsubs_server.threading;

public import std.parallelism;


/// global task pool for game object model calculations
__gshared TaskPool g_taskPool;

shared static this()
{
	g_taskPool = new TaskPool(totalCPUs);
}