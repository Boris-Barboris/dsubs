module dsubs_server.ai.bt;

import std.algorithm.comparison: min, max;

import dsubs_common.containers.array;


enum ExecutionResult
{
	running,
	success,
	failure
}


class BehavourTreeNode
{
	private
	{
		ControlFlowNode m_parent;
		string m_description;
	}

	final @property string description() const { return m_description; }

	final @property ControlFlowNode parent() const { return m_parent; }

	@property void parent(ControlFlowNode rhs)
	{
		if (m_parent && rhs !is m_parent)
			m_parent.onChildDetached(this);
		if (rhs)
			rhs.onChildAttached(this);
		m_parent = rhs;
	}

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

	abstract void onChildDetached(BehavourTreeNode oldChild);
	abstract void onChildAttached(BehavourTreeNode newChild);
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

	final override void onChildDetached(BehavourTreeNode oldChild)
	{
		m_children.removeFirst(oldChild);
		m_lastIdxMemory = min(m_lastIdxMemory, m_children.length);
	}

	final override void onChildAttached(BehavourTreeNode newChild)
	{
		m_children ~= newChild;
	}

	final @property void children(BehavourTreeNode[] newChildrenArray)
	{
		m_lastIdxMemory = 0;
		foreach (child; m_children)
			child.parent = null;
		m_children.reserve(newChildrenArray.length);
		foreach (child; newChildrenArray)
			child.parent = this;
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
		child.parent = this;
	}

	final override void onChildDetached(BehavourTreeNode oldChild)
	{
		if (m_child is oldChild)
			m_child = null;
	}

	final override void onChildAttached(BehavourTreeNode newChild)
	{
		m_child = newChild;
	}

	final @property BehavourTreeNode child()
	{
		return m_child;
	}

	final @property void child(BehavourTreeNode rhs)
	{
		if (m_child)
			m_child.parent = null;
		rhs.parent = this;
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
		if (predicate())
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