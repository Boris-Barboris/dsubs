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

	override string toString() const { return description; }

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


final class Sleep: ControlFlowNode
{
	private
	{
		int m_sleepRemaining;
		int m_minToSleep, m_maxToSleep;
	}

	this(string description, int ticksToSleepFor,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(ticksToSleepFor >= 0);
		super(description, file, line);
		m_minToSleep = m_maxToSleep = ticksToSleepFor;
	}

	this(string description, int minTicksToSleep, int maxTicksToSleep,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(minTicksToSleep >= 0);
		assert(maxTicksToSleep >= minTicksToSleep);
		super(description, file, line);
		m_minToSleep = minTicksToSleep;
		m_maxToSleep = maxTicksToSleep;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		if (m_sleepRemaining == 0)
		{
			if (m_maxToSleep != m_minToSleep)
				m_sleepRemaining = uniform!"[]"(m_minToSleep, m_maxToSleep);
			else
				m_sleepRemaining = m_minToSleep;
		}
		if (consumeMinOfTicks(ticks, ticks, m_sleepRemaining))
			return ExecutionResult.success;
		return ExecutionResult.running;
	}
}


final class Loop: ControlFlowNode
{
	private
	{
		int m_counter;
		int m_minLoops, m_maxLoops;
		BehaviourTreeNode m_child;
	}

	this(string description, BehaviourTreeNode child, int loopCount,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(child);
		super(description, file, line);
		m_child = child;
		m_minLoops = m_maxLoops = loopCount;
	}

	this(string description, BehaviourTreeNode child, int minLoops, int maxLoops,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(child);
		super(description, file, line);
		m_child = child;
		m_minLoops = minLoops;
		m_maxLoops = maxLoops;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		if (m_counter <= 0)
		{
			if (m_minLoops != m_maxLoops)
				m_counter = uniform!"[]"(m_minLoops, m_maxLoops);
			else
				m_counter = m_minLoops;
		}
		while (ticks > 0 && m_counter > 0)
		{
			ExecutionResult childRes = m_child.execute(ticks);
			final switch (childRes)
			{
				case ExecutionResult.running:
					return childRes;
				case ExecutionResult.failure:
					// child failure breaks the loop
					m_counter = 0;
					return childRes;
				case ExecutionResult.success:
					m_counter--;
			}
		}
		if (m_counter > 0)
			return ExecutionResult.running;
		return ExecutionResult.success;
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
		this.m_children = children;
		this.memory = memory;
	}

	// @property void children(BehaviourTreeNode[] newChildrenArray)
	// {
	// 	m_lastIdxMemory = 0;
	// 	m_children = newChildrenArray;
	// }

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


/// State node for a state machine, defined later
final class SMState: ControlFlowNode
{
	private
	{
		string m_state;
		BehaviourTreeNode m_child;
	}

	this(string stateName, BehaviourTreeNode child,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(child);
		super("SMState: " ~ stateName, file, line);
		m_child = child;
		m_state = stateName;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		return m_child.doExecute(ticks);
	}
}


struct StateVar
{
	string stateName;
	bool changedFlag;

	string readAndReset()
	{
		changedFlag = false;
		return stateName;
	}

	void setAndUpdate(string newStateName)
	{
		changedFlag = (newStateName != stateName);
		stateName = newStateName;
	}
}


final class FStateMachine: LinearChildrenNode
{
	private
	{
		StateVar* m_stateVar;
	}

	this(string description, StateVar* stateVar, SMState[] children,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, cast (BehaviourTreeNode[]) children, true,
			file, line);
		assert(stateVar);
		m_stateVar = stateVar;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		assert(m_stateVar);
		do
		{
			string stateName = m_stateVar.readAndReset();
			for (size_t i = 0; i < m_children.length; i++)
			{
				SMState child = cast(SMState) m_children[i];
				assert(child);
				if (child.stateName != stateName)
				{
					if (i == m_children.length - 1)
					{
						// no node for stateName
						return ExecutionResult.failure;
					}
					continue;
				}
				// we have found the state
				ExecutionResult res = child.execute(ticks);
				if (res == ExecutionResult.failure ||
						res == ExecutionResult.running)
					return res;
			}
			// child.execute could have changed the state using SwitchSMState
			// node. If the child succeeded and there are ticks left,
			// we should immediately jump to the new state and execute it.
		} while (m_stateVar.changedFlag && ticks > 0);
		return ExecutionResult.success;
	}
}


final class SwitchSMState: ControlFlowNode
{
	private
	{
		string m_newState;
		StateVar* m_stateVar;
	}

	this(string newState, StateVar* stateVar,
		string file = __FILE__, size_t line = __LINE__)
	{
		super("SwitchSMState: " ~ newState, file, line);
		assert(stateVar);
		m_newState = newState;
		m_stateVar = stateVar;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		assert(m_stateVar);
		m_stateVar.setAndUpdate(m_newState);
		return ExecutionResult.success;
	}
}


/// Executes children in sequential order, switching to next when previous
/// returned 'success'.
class Sequence: LinearChildrenNode
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


/// Sequence that has memory = true
final class SequenceMem: Sequence
{
	this(string description, BehaviourTreeNode[] children,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, true, file, line);
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
/// Commonly knows as BT Selector.
class Fallback: LinearChildrenNode
{
	this(string description, BehaviourTreeNode[] children, bool memory = false,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, memory, file, line);
	}

	protected final override ExecutionResult doExecute(ref int ticks)
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


/// Fallback that has memory = true
final class FallbackMem: Fallback
{
	this(string description, BehaviourTreeNode[] children,
		string file = __FILE__, size_t line = __LINE__)
	{
		super(description, children, true, file, line);
	}
}


/// Distributes ticks among the children in slices until all children either return final
/// status (either success or failure), or the ticks are exhausted. Returns failure only
/// if all children have returned failure.
final class RoundRobin: LinearChildrenNode
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

	@property int timeSlice() const { return m_timeSlice; }

	@property void timeSlice(int rhs) { m_timeSlice = rhs; }

	protected final override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		if (m_children.length == 0)
			return ExecutionResult.failure;
		int i = m_lastIdxMemory.to!int - 1;
		scope(exit) m_lastIdxMemory = (i + 1) % m_children.length.to!int;
		m_childrenResults.length = m_children.length;
		m_childrenResults[] = ExecutionResult.running;
		int finalResults = 0;
		int infiniteLoopProtection = 5000;
		while (ticks > 0)
		{
			if (--infiniteLoopProtection <= 0)
				throw new Exception("infiniteLoopProtection fault in RoundRobin BT node");
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
/// have returned success. Clone ticks and distributes them to all children.
/// The original ticks counter is reduced by the largest number of tickes
/// consumed by it's children.
final class Parallel: LinearChildrenNode
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
final class Condition: BehaviourTreeNode
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


/// Simple action that consumes 'cost' ticks and then runs onCostConsumedDlg
class Action: ActionNode
{
	protected
	{
		int m_ticksCost;
		void delegate() m_onCostConsumedDlg;
	}

	this(string description, int cost, void delegate() onCostConsumedDlg,
		string file = __FILE__, size_t line = __LINE__)
	{
		assert(cost >= 0);
		super(description, file, line);
		m_onCostConsumedDlg = onCostConsumedDlg;
		m_ticksCost = cost;
		m_ticksToFinish = cost;
	}

	protected override ExecutionResult doExecute(ref int ticks)
	{
		assert(ticks > 0);
		if (consumeMinOfTicks(m_ticksCost, m_ticksToFinish, ticks))
		{
			m_ticksToFinish = m_ticksCost;
			m_onCostConsumedDlg();
			// I'm not sure it's ever useful to have an option to return failure here.
			// It is preferable to precede Action with a condition that should prevent the
			// failure.
			return ExecutionResult.success;
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