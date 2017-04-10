module threading.taskgraph;

import core.atomic;
import core.cpuid;
import core.thread;
import core.sync.condition;
import core.sync.barrier;
import core.sync.mutex;
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
	/// more work is required by this generator.
	Action generate();
}

/// Collection of generators, that are guaranteed to be capable of performing
/// work in parallel. In game loop it's usually a stage. For example, physics
/// stage, or rendering stage, or maybe user event processing stage.
class TaskBlock
{
	TaskGenerator[] generators;

	protected uint cursor = 0;

	Action generate()
	{
		for (int i = cursor; i < generators.length; i++)
		{
			auto action = generators[i].generate();
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
	public TaskBlock[] blocks;
	protected ThreadGroup threads;

	protected Condition block_done;		// last worker signals dispatcher that
										// he's done via this condition
	
	protected Barrier barrier;			// barrier to await next block start on
	protected Mutex consume_mutex;
	public const uint thread_count;
	
	protected shared uint running_threads = 0;
	protected uint current_block = 0;

	// set to true when we're disposing
	protected bool exit_requested = false;

	this(uint thread_count = coresPerCPU)
	{
		this.thread_count = thread_count;
		consume_mutex = new Mutex;
		block_done = new Condition(new Mutex);
		// thread_count + 1 because dispatcher thread that changes
		// current block needs to wait on barrier too.
		barrier = new Barrier(thread_count + 1);
		threads = new ThreadGroup;
		for (uint i = 0; i < thread_count; i++)
		{
			threads.create(&worker_function);
		}
	}

	/// Tell workers to stop. Better be called from dispatcher thread.
	void dispose()
	{
		exit_requested = true;
		barrier.wait();
		threads.joinAll();
	}

	private Action consume_action()
	{
		synchronized(consume_mutex)
		{			
			return blocks[current_block].generate();
		}
	}

	/// Main loop of worker thread
	private void worker_function()
	{
		while (true)
		{
			barrier.wait();		// wait for next block start
			if (exit_requested)
				return;
			auto action = consume_action();
			while (action != null)
			{
				handle_action(action);
				action = consume_action();
			}
			// we're finished on this block, need to report to dispatcher
			assert(running_threads > 0);
			atomicOp!"-="(running_threads, 1);
			if (running_threads == 0)
				block_done.notify();
		}
	}

	/// Overload to handle errors.
	protected void handle_action(Action action)
	{
		action();
	}

	/// Walk through whole graph once. Synchronous call - caller
	/// thread serves as a dispatcher.
	void run_cycle()
	{
		if (blocks.length == 0)
			return;
		// for each task block
		for (current_block = 0; current_block < blocks.length; current_block++)
		{
			running_threads = thread_count;
			// set workers loose by entering barrier			
			barrier.wait();
			// wait for the signal from last worker
			block_done.wait();
		}
	}
}




// Some live tests

unittest
{
	import std.conv;
	//import std.stdio;
	import core.time;

	//writeln("Running test_graph_runner");

	shared string[] result;

	void append(string str)
	{
		synchronized
		{
			result ~= str;
		}
	}

	class PrinterGenerator: TaskGenerator
	{
		string str;
		int counter = 0;

		this(string what_to_print)
		{
			str = what_to_print;
		}

		void do_print()
		{
			//writeln(str ~ to!string(Thread.getThis.id));
			append(str);
			Thread.sleep( dur!("msecs")(50) );
		}

		Action generate()
		{
			if (counter < 5)
			{
				counter++;
				return &do_print;
			}
			return null;
		}
	}

	auto gen1 = new PrinterGenerator("gen1 ");
	auto gen2 = new PrinterGenerator("gen2 ");
	auto gen3 = new PrinterGenerator("gen3 ");

	auto block = new TaskBlock();
	block.generators = [gen1, gen2, gen3];

	auto graph = new TaskGraph(3);
	graph.blocks = [block];
	graph.run_cycle();
	graph.dispose();

	assert(result.length == 15);
}