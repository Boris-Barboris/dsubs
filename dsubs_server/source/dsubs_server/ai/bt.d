module dsubs_server.ai.bt;

import std.algorithm.comparison: min, max;
import std.algorithm: canFind, minElement;

import std.conv: to;

import dsubs_common.containers.array;

import dsubs_server.common;


enum ExecutionResult: byte
{
	running,
	success,
	failure
}

bool isFinalResult(ExecutionResult res)
{
	return res != ExecutionResult.running;
}


class BehavourTreeNode
{
	private
	{
		string m_description;
	}

	final @property string description() const { return m_description; }

	this(string description, string file, size_t line)
	{
		m_description = file ~ ":" ~ line.to!string ~ " " ~ description;
	}

	/// Propagate ticks and return the execution result.
	abstract ExecutionResult execute(ref int ticks);
}


class ControlFlowNode: BehavourTreeNode
{
	this(string description, string file, size_t line)
	{
		super(description, file, line);
	}
}


abstract class LinearChildrenNode: ControlFlowNode
{
	protected
	{
		BehavourTreeNode[] m_children;
		size_t m_lastIdxMemory;
	}

	/// Sequence simulator
	bool memory;

	this(string description, BehavourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, file, line);
		this.children = children;
		this.memory = memory;
	}

	final @property void children(BehavourTreeNode[] newChildrenArray)
	{
		m_lastIdxMemory = 0;
		m_children = newChildrenArray;
	}
}


abstract class DecoratorNode: ControlFlowNode
{
	protected
	{
		BehavourTreeNode m_child;
	}

	this(string description, BehavourTreeNode child, string file, size_t line)
	{
		super(description, file, line);
		m_child = child;
	}

	final @property BehavourTreeNode child()
	{
		return m_child;
	}

	final @property void child(BehavourTreeNode rhs)
	{
		m_child = rhs;
	}
}


final class SequenceNode: LinearChildrenNode
{

	this(string description, BehavourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, memory, file, line);
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		for (size_t i = memory ? m_lastIdxMemory : 0; i < m_children.length; i++)
		{
			if (memory)
				m_lastIdxMemory = i;
			if (ticks <= 0)
				return ExecutionResult.running;
			BehavourTreeNode child = m_children[i];
			ExecutionResult res = child.execute(ticks);
			if (res == ExecutionResult.running || res == ExecutionResult.failure)
				return res;
		}
		if (memory)
			m_lastIdxMemory = 0;
		return ExecutionResult.success;
	}
}


/// Returns true if the local ticks counter has reached zero.
bool consumeLocalTicks(int consume, ref int ticksLeftLocal, ref int ticksLeftGlobal)
{
	assert(ticksLeftLocal >= 0);
	assert(ticksLeftGlobal >= 0);
	assert(consume >= 0);
	int delta = min(consume, ticksLeftLocal, ticksLeftGlobal);
	ticksLeftLocal -= delta;
	ticksLeftGlobal -= delta;
	return ticksLeftLocal == 0;
}


final class FallbackNode: LinearChildrenNode
{
	this(string description, BehavourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, memory, file, line);
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		for (size_t i = memory ? m_lastIdxMemory : 0; i < m_children.length; i++)
		{
			if (memory)
				m_lastIdxMemory = i;
			if (ticks <= 0)
				return ExecutionResult.running;
			BehavourTreeNode child = m_children[i];
			ExecutionResult res = child.execute(ticks);
			if (res == ExecutionResult.running || res == ExecutionResult.success)
				return res;
		}
		if (memory)
			m_lastIdxMemory = 0;
		return ExecutionResult.failure;
	}
}


/// Distributes ticks among the children until all children either return final
/// status (either success or failure), or the ticks are exhausted. Returns failure only
/// if all children have returned failure.
final class RoundRobinNode: LinearChildrenNode
{
	this(string description, BehavourTreeNode[] children, int timeSlice,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, true, file, line);
		m_timeSlice = timeSlice;
	}

	private
	{
		int m_timeSlice;
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		if (m_children.length == 0)
			return ExecutionResult.failure;
		int i = m_lastIdxMemory.to!int - 1;
		scope(exit) m_lastIdxMemory = (i + 1) % m_children.length.to!int;
		ExecutionResult[] childrenResults;
		childrenResults.length = m_children.length;
		while (ticks > 0)
		{
			i = (i + 1) % m_children.length.to!int;
			if (isFinalResult(childrenResults[i]))
				continue;
			int currentSlice = min(m_timeSlice, ticks);
			BehavourTreeNode child = m_children[i];
			int ticksToSpend = currentSlice;
			childrenResults[i] = child.execute(ticksToSpend);
			int spentTicks = currentSlice - ticksToSpend;
			ticks -= spentTicks;
			assert(ticks >= 0);
			assert((childrenResults[i] != ExecutionResult.running) || spentTicks > 0,
				"subtree returned running but did not reduce ticks");
			// TODO: maybe optimize linear search
			if (!canFind(childrenResults, ExecutionResult.running))
			{
				if (canFind(childrenResults, ExecutionResult.success))
					return ExecutionResult.success;
				else
					return ExecutionResult.failure;
			}
		}
		return ExecutionResult.running;
	}
}


final class ParallelNode: LinearChildrenNode
{
	int successThreshold;

	this(string description, BehavourTreeNode[] children, int successThreshold = 1,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, false, file, line);
		this.successThreshold = successThreshold;
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		if (m_children.length == 0)
			return successThreshold <= 0 ? ExecutionResult.success : ExecutionResult.failure;
		int[] childTicks;
		childTicks.length = m_children.length;
		childTicks[] = ticks;
		int successCount;
		int failureCount;
		foreach (i, child; m_children)
		{
			ExecutionResult res = child.execute(childTicks[i]);
			if (res == ExecutionResult.success)
				successCount++;
			else if (res == ExecutionResult.failure)
				failureCount++;
		}
		ticks = minElement(childTicks);
		if (successCount >= successThreshold)
			return ExecutionResult.success;
		if (failureCount >= m_children.length - successThreshold + 1)
			return ExecutionResult.failure;
		return ExecutionResult.running;
	}
}


final class ConditionNode: BehavourTreeNode
{
	bool delegate() predicate;

	this(string description, bool delegate() pred,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, file, line);
		predicate = pred;
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		bool res = predicate();
		// trace("ConditionNode ", description, " predicate returned ", res);
		if (res)
			return ExecutionResult.success;
		else
			return ExecutionResult.failure;
	}
}


abstract class ActionNode: BehavourTreeNode
{
	protected
	{
		/// ticks needed to finish the job.
		int m_ticksLeft;
	}

	invariant
	{
		assert(m_ticksLeft >= 0);
	}

	this(string description, string file, size_t line)
	{
		super(description, file, line);
	}
}


abstract class FixedCostActionNode: ActionNode
{
	protected
	{
		int m_ticksCost;
	}

	this(string description, int cost,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(cost >= 0);
		super(description, file, line);
		m_ticksCost = cost;
		m_ticksLeft = cost;
	}

	@property bool shouldBeRunning()
	{
		return true;
	}

	abstract ExecutionResult onTicksConsumed();

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		if (!shouldBeRunning)
		{
			m_ticksLeft = m_ticksCost;
			return ExecutionResult.failure;
		}
		if (consumeLocalTicks(m_ticksCost, m_ticksLeft, ticks))
		{
			m_ticksLeft = m_ticksCost;
			// trace("FixedCostActionNode ", description, " reached fire time");
			return onTicksConsumed();
		}
		else
			return ExecutionResult.running;
	}
}


final class NopAction: ActionNode
{
	this(string file = __FILE__, size_t line = __LINE__)
	{
		super("No-op action", file, line);
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		return ExecutionResult.success;
	}
}