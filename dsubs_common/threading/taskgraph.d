module threading.taskgraph;

import core.cpuid;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.concurrency;
import std.container.dlist;

/// Abstract action generator, that provides runtime with actions
/// to perform. It can be a component manager, for example animation
/// component, that generates tasks to update states of 
/// all animated entities.
interface TaskGenerator
{
	/// Returns concurrent action to perform, or null if no
	/// more work is needed for this generator.
	void delegate() generate();
}

/// Collection of generators, that are guaranteed to be capable of performing
/// work in parallel. In game loop it's usually a stage. For example, physics
/// stage, or rendering stage, or maybe user event processing stage.
class TaskBlock
{
	DList!TaskGenerator generators;

	synchronized void delegate() generate()
	{
		foreach (g; generators)
		{
			auto action = g.generate();
			if (action != null)
				return action;
		}
		return null;
	}
}

/// Whole task graph, that represents one game loop revolution.
/// Performs thread managing.
class TaskGraph
{
	private DList!TaskBlock blocks;
	private Tid[] threads;
	private uint[Tid] tid_map;
	private uint[] thread_queues;

	this(uint thread_count = coresPerCPU)
	{
		// Spawn threads and make them listen
		threads = new Tid[thread_count];
		for (uint i = 0; i < thread_count; i++)
		{
			threads[i] = spawn(cast(shared void delegate(Tid)) &worker_function, thisTid);
			tid_map[threads[i]] = i;
		}
		thread_queues = new uint[thread_count];
	}

	/// Explicit resource deallocation
	void dispose()
	{

	}

	/// Main loop of worker thread
	private void worker_function(Tid owner)
	{
		bool stop_requested = false;
		while (!stop_requested)
		{
			// Perform the action passed or exit if any int was passed
			receive (
				(void delegate() action) 
				{ 
					handle_action(action);
					send(owner, thisTid);		// notify dispatcher thread that we're done
				},
				(int code) { stop_requested = true; }
			);
		}
		send(owner, thisTid);
	}

	/// Overload to handle errors.
	protected void handle_action(void delegate() action)
	{
		action();
	}

	/// Walk through whole graph once. Synchronous call - caller
	/// thread serves as a dispatcher.
	void run_cycle()
	{
		// for each task block
		foreach (block; blocks)
		{
			auto action = block.generate();
			while (action != null)
			{
				int free_worker = find_free_worker();
				if (free_worker == -1)
				{
					// all workers are busy, let's wait
					Tid id = receiveOnly!Tid();
					uint index = tid_map[id];
					// give this new action to the worker
					send(id, action);
				}
				else
				{
					Tid id = threads[free_worker];
					send(id, action);
					thread_queues[free_worker]++;
				}
				action = block.generate();
			}
			// we're out of actions, let's wait for all workers
			// to finish the block
			wait_all();
		}
	}

	static immutable uint QUEUE_SIZE = 2;

	private int find_free_worker()
	{
		for (int i = 0; i < QUEUE_SIZE; i++)
			for (int j = 0; j < threads.length; j++)
			{
				if (thread_queues[j] == i)
					return j;
			}
		return -1;
	}

	private void wait_all()
	{
		auto busy_count = sum(thread_queues);
		for (int i = 0; i < busy_count; i++)
			receiveOnly!Tid();
		// reset thread queues counters
		for (int i = 0; i < threads.length; i++)
			thread_queues[i] = 0;
	}
}
