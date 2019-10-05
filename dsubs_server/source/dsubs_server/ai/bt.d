module dsubs_server.ai.bt;

import std.algorithm.comparison: min, max;
import std.algorithm: canFind;

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

	this(string description)
	{
		m_description = description;
	}

	/// Propagate ticks and return the execution result.
	abstract ExecutionResult execute(ref int ticks);
}


class ControlFlowNode: BehavourTreeNode
{
	this(string description)
	{
		super(description);
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

	this(string description, BehavourTreeNode[] children, bool memory = false)
	{
		super(description);
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

	this(string description, BehavourTreeNode child)
	{
		super(description);
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

	this(string description, BehavourTreeNode[] children, bool memory = false)
	{
		super(description, children, memory);
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


final class FallbackNode: LinearChildrenNode
{
	this(string description, BehavourTreeNode[] children, bool memory = false)
	{
		super(description, children, memory);
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
	this(string description, BehavourTreeNode[] children, int timeSlice)
	{
		super(description, children, true);
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
			return ExecutionResult.success;
		ptrdiff_t i = m_lastIdxMemory - 1;
		scope(exit) m_lastIdxMemory = max(0, i.to!size_t);
		ExecutionResult[] childrenResults;
		childrenResults.length = m_children.length;
		while (ticks > 0)
		{
			i = (i + 1) % m_children.length;
			if (isFinalResult(childrenResults[i]))
				continue;
			int currentSlice = min(m_timeSlice, ticks);
			BehavourTreeNode child = m_children[i];
			int ticksToSpend = currentSlice;
			ExecutionResult res = child.execute(ticksToSpend);
			int spentTicks = currentSlice - ticksToSpend;
			ticks -= spentTicks;
			assert(ticks >= 0);
			childrenResults[i] = res;
			assert(spentTicks > 0, "subtree returned running but did not reduce ticks");
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

	this(string description, BehavourTreeNode[] children, int successThreshold)
	{
		super(description, children);
		this.successThreshold = successThreshold;
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
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
			if (res == ExecutionResult.failure)
				failureCount++;
		}
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

	this(string description, bool delegate() pred)
	{
		super(description);
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

	this(string description)
	{
		super(description);
	}
}


abstract class FixedCostActionNode: ActionNode
{
	protected
	{
		int m_ticksCost;
	}

	this(string description, int cost)
	{
		assert(cost >= 0);
		super(description);
		m_ticksCost = cost;
		m_ticksLeft = cost;
	}

	abstract ExecutionResult onTicksConsumed();

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		int delta = min(m_ticksCost, ticks, m_ticksLeft);
		m_ticksLeft -= delta;
		if (m_ticksLeft == 0)
		{
			m_ticksLeft = m_ticksCost;
			trace("FixedCostActionNode ", description, " reached fire time");
			return onTicksConsumed();
		}
		else
			return ExecutionResult.running;
	}
}


final class NopAction: ActionNode
{
	this()
	{
		super("No-op action");
	}

	override ExecutionResult execute(ref int ticks)
	{
		assert(ticks > 0);
		return ExecutionResult.success;
	}
}