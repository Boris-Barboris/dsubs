module threading.taskgraph;

import core.cpuid;
import core.thread;
import std.algorithm.iteration;
import std.algorithm.searching;

alias Action = void delegate();

/// Abstract action generator, that provides runtime with actions
/// to perform. It can be a component manager, for example animation
/// component, that generates tasks to update states of 
/// all animated entities.
interface TaskGenerator
{
	/// Returns concurrent action to perform, or null if no
	/// more work is needed for this generator.
	Action generate();
}

/// Collection of generators, that are guaranteed to be capable of performing
/// work in parallel. In game loop it's usually a stage. For example, physics
/// stage, or rendering stage, or maybe user event processing stage.
class TaskBlock
{
	TaskGenerator[] generators;

	private uint cursor = 0;

	Action generate()
	{
		for (int i = cursor; i < generatos.length; i++)
		{
			auto g = generators[i];
			auto action = g.generate();
			if (action != null)
				return action;
		}
		cursor = 0;
		return null;
	}
}

/// Whole task graph, that represents one game loop revolution.
/// Performs thread managing.
class TaskGraph
{
	private TaskBlock[] blocks;
	private ThreadGroup threads;

	this(uint thread_count = coresPerCPU)
	{
		threads = new ThreadGroup;
		for (uint i = 0; i < thread_count; i++)
		{
			threads.create(&worker_function);
		}
	}

	/// Explicit resource deallocation
	void dispose()
	{

	}

	/// Main loop of worker thread
	private void worker_function()
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
					auto id = receiveOnly!Tid();
					uint index = tid_map[id];
					// give this new action to the worker
					send(id, action);
				}
				else
				{
					auto id = threads[free_worker];
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
