/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.ai.bt;

import std.algorithm.comparison: min, max;
import std.algorithm: canFind, minElement;
import std.conv: to;
import std.json;

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


class BehaviourTreeNode
{
	private
	{
		string m_description;
	}

	final @property string description() const { return m_description; }

	this(string description, string file, size_t line)
	{
		m_description = classBaseName(this) ~ " " ~ file ~ ":" ~
			line.to!string ~ " " ~ description;
	}

	override string toString() { return description; }

	/// Propagate and consume ticks and return the execution result.
	ExecutionResult execute(ref int ticks)
	{
		m_wasExecutedInLastEpoch = true;
		int ticksBefore = ticks;
		m_execResultInLastEpoch = doExecute(ticks);
		m_ticksConsumedInLastEpoch = ticksBefore - ticks;
		return m_execResultInLastEpoch;
	}

	abstract protected ExecutionResult doExecute(ref int ticks);

	protected
	{
		bool m_wasExecutedInLastEpoch;
		int m_ticksConsumedInLastEpoch;
		ExecutionResult m_execResultInLastEpoch;
	}

	JSONValue toJson()
	{
		JSONValue[string] objectFields;
		JSONValue res = JSONValue(objectFields);
		res["nodeType"] = this.classBaseName;
		res["description"] = m_description;
		res["wasExecuted"] = m_wasExecutedInLastEpoch;
		if (m_wasExecutedInLastEpoch)
		{
			res["ticksConsumed"] = m_ticksConsumedInLastEpoch;
			res["execResult"] = m_execResultInLastEpoch.to!string;
		}
		return res;
	}

	/// Used to reset observer-related counters
	void markNewObservationEpoch()
	{
		m_wasExecutedInLastEpoch = false;
		m_ticksConsumedInLastEpoch = 0;
	}
}


class ControlFlowNode: BehaviourTreeNode
{
	this(string description, string file, size_t line)
	{
		super(description, file, line);
	}
}


/// Abstract control-flow node that operates on the array of children
abstract class LinearChildrenNode: ControlFlowNode
{
	protected
	{
		BehaviourTreeNode[] m_children;

		// When true, control node will remember the last child it stopped execution
		// on in the previous "execute" call.
		bool memory;
		size_t m_lastIdxMemory;
	}

	this(string description, BehaviourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, file, line);
		this.children = children;
		this.memory = memory;
	}

	final @property void children(BehaviourTreeNode[] newChildrenArray)
	{
		m_lastIdxMemory = 0;
		m_children = newChildrenArray;
	}

	override JSONValue toJson()
	{
		JSONValue res = super.toJson();
		res["lastIdxMemory"] = m_lastIdxMemory;
		res["children"] = m_children.map!(c => c.toJson()).array;
		return res;
	}

	override void markNewObservationEpoch()
	{
		super.markNewObservationEpoch();
		foreach (c; m_children)
			c.markNewObservationEpoch();
	}
}


// probably not needed
// abstract class DecoratorNode: ControlFlowNode
// {
// 	protected
// 	{
// 		BehaviourTreeNode m_child;
// 	}

// 	this(string description, BehaviourTreeNode child, string file, size_t line)
// 	{
// 		super(description, file, line);
// 		m_child = child;
// 	}

// 	final @property BehaviourTreeNode child()
// 	{
// 		return m_child;
// 	}

// 	final @property void child(BehaviourTreeNode rhs)
// 	{
// 		m_child = rhs;
// 	}
// }


/// Executes children in sequential order, switching to next when previous
/// returned 'success'.
final class SequenceNode: LinearChildrenNode
{

	this(string description, BehaviourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, memory, file, line);
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		for (size_t i = memory ? m_lastIdxMemory : 0; i < m_children.length; i++)
		{
			if (memory)
				m_lastIdxMemory = i;
			if (ticks <= 0)
				return ExecutionResult.running;
			BehaviourTreeNode child = m_children[i];
			ExecutionResult res = child.execute(ticks);
			if (res == ExecutionResult.running || res == ExecutionResult.failure)
				return res;
		}
		if (memory)
			m_lastIdxMemory = 0;
		return ExecutionResult.success;
	}
}


/// Consumes at most 'consume' ticks from both 'ticks1' and 'ticks2', without running
/// them into the negatives. Returns true if the ticks1 counter has reached zero.
bool consumeMinOfTicks(int consume, ref int ticks1, ref int ticks2)
{
	assert(ticks1 >= 0);
	assert(ticks2 >= 0);
	assert(consume >= 0);
	int delta = min(consume, ticks1, ticks2);
	ticks1 -= delta;
	ticks2 -= delta;
	return ticks1 == 0;
}


/// Executes children in sequential order, switching to next when previous
/// returned 'failure'. Finishes on the first child that has returned success.
/// Also commonly knows as BT Selector.
final class FallbackNode: LinearChildrenNode
{
	this(string description, BehaviourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, memory, file, line);
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		for (size_t i = memory ? m_lastIdxMemory : 0; i < m_children.length; i++)
		{
			if (memory)
				m_lastIdxMemory = i;
			if (ticks <= 0)
				return ExecutionResult.running;
			BehaviourTreeNode child = m_children[i];
			ExecutionResult res = child.execute(ticks);
			if (res == ExecutionResult.running)
				return res;
			if (res == ExecutionResult.success)
			{
				if (memory)
					m_lastIdxMemory = 0;
				return res;
			}
		}
		if (memory)
			m_lastIdxMemory = 0;
		return ExecutionResult.failure;
	}
}


/// Distributes ticks among the children in slices until all children either return final
/// status (either success or failure), or the ticks are exhausted. Returns failure only
/// if all children have returned failure.
final class RoundRobinNode: LinearChildrenNode
{
	this(string description, BehaviourTreeNode[] children, int timeSlice,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, true, file, line);
		m_childrenResults.length = children.length;
		m_timeSlice = timeSlice;
	}

	private
	{
		int m_timeSlice;
		ExecutionResult[] m_childrenResults;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		if (m_children.length == 0)
			return ExecutionResult.failure;
		int i = m_lastIdxMemory.to!int - 1;
		scope(exit) m_lastIdxMemory = (i + 1) % m_children.length.to!int;
		m_childrenResults.length = m_children.length;
		m_childrenResults[] = ExecutionResult.running;
		int finalResults = 0;
		while (ticks > 0)
		{
			i = (i + 1) % m_children.length.to!int;
			if (isFinalResult(m_childrenResults[i]))
				continue;
			int currentSlice = min(m_timeSlice, ticks);
			BehaviourTreeNode child = m_children[i];
			int ticksToSpend = currentSlice;
			m_childrenResults[i] = child.execute(ticksToSpend);
			int spentTicks = currentSlice - ticksToSpend;
			ticks -= spentTicks;
			assert(ticks >= 0);
			assert((m_childrenResults[i] != ExecutionResult.running) || spentTicks > 0,
				"subtree returned running but did not reduce ticks");
			if (isFinalResult(m_childrenResults[i]))
				finalResults++;
			if (finalResults >= m_childrenResults.length)
			{
				if (canFind(m_childrenResults, ExecutionResult.success))
					return ExecutionResult.success;
				else
					return ExecutionResult.failure;
			}
		}
		return ExecutionResult.running;
	}

	override JSONValue toJson()
	{
		JSONValue res = super.toJson();
		res["timeSlice"] = m_timeSlice;
		return res;
	}
}


/// Returns success if more or equal to 'successThreshold' number of children
/// have returned success. Clones ticks and distributes it all children.
/// The original ticks counter is reduced by the largest number of tickes
/// consumed by it's children.
final class ParallelNode: LinearChildrenNode
{
	private
	{
		int m_successThreshold;
		int[] m_childTicks;
	}

	this(string description, BehaviourTreeNode[] children, int successThreshold = 1,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, false, file, line);
		m_childTicks.length = children.length;
		this.m_successThreshold = successThreshold;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		if (m_children.length == 0)
			return m_successThreshold <= 0 ?
				ExecutionResult.success : ExecutionResult.failure;
		m_childTicks.length = m_children.length;
		m_childTicks[] = ticks;
		int successCount;
		int failureCount;
		foreach (i, child; m_children)
		{
			ExecutionResult res = child.execute(m_childTicks[i]);
			if (res == ExecutionResult.success)
				successCount++;
			else if (res == ExecutionResult.failure)
				failureCount++;
		}
		ticks = minElement(m_childTicks);
		if (successCount >= m_successThreshold)
			return ExecutionResult.success;
		if (failureCount >= m_children.length - m_successThreshold + 1)
			return ExecutionResult.failure;
		return ExecutionResult.running;
	}
}


/// Simply returns 'success' or 'failure' based on the return value of a predicate.
final class ConditionNode: BehaviourTreeNode
{
	bool delegate() predicate;

	this(string description, bool delegate() pred,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, file, line);
		predicate = pred;
	}

	protected override ExecutionResult doExecute(ref int ticks)
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


abstract class ActionNode: BehaviourTreeNode
{
	protected
	{
		/// ticks needed to finish the job.
		int m_ticksToFinish;
	}

	invariant
	{
		assert(m_ticksToFinish >= 0);
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
		bool m_invertShouldBeRunning;
	}

	this(string description, int cost, bool invertShouldBeRunning = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(cost >= 0);
		super(description, file, line);
		m_ticksCost = cost;
		m_ticksToFinish = cost;
		m_invertShouldBeRunning = invertShouldBeRunning;
	}

	@property bool invertShouldBeRunning() const { return m_invertShouldBeRunning; }
	@property void invertShouldBeRunning(bool rhs) { m_invertShouldBeRunning = rhs; }

	/// FIXME: Heresy to BT execution model, essentially in-built ConditionNode that
	/// is overriden in child classes in order to improve semantic code locality.
	@property bool shouldBeRunning()
	{
		return true;
	}

	abstract ExecutionResult onTicksCostConsumed();

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		if (!shouldBeRunning)
		{
			// resets progress
			m_ticksToFinish = m_ticksCost;
			if (m_invertShouldBeRunning)
				return ExecutionResult.success;
			return ExecutionResult.failure;
		}
		if (consumeMinOfTicks(m_ticksCost, m_ticksToFinish, ticks))
		{
			m_ticksToFinish = m_ticksCost;
			// trace("FixedCostActionNode ", description, " reached fire time");
			return onTicksCostConsumed();
		}
		else
			return ExecutionResult.running;
	}

	override JSONValue toJson()
	{
		JSONValue res = super.toJson();
		res["ticksCost"] = m_ticksCost;
		res["ticksToFinish"] = m_ticksToFinish;
		return res;
	}
}


// probably not needed
// final class NopAction: ActionNode
// {
// 	this(string file = __FILE__, size_t line = __LINE__)
// 	{
// 		super("No-op action", file, line);
// 	}

// 	protected override ExecutionResult doExecute(ref int ticks)
// 	{
// 		assert(ticks > 0);
// 		return ExecutionResult.success;
// 	}
// }