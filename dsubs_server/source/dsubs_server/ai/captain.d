module dsubs_server.ai.captain;

import dsubs_common.containers.circqueue;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.weaponry;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.ai.common;
import dsubs_server.ai.helmsman;

public import dsubs_server.ai.common: BOT_DIFFICULTY;


abstract class AICrewTemp: Captain
{
	void afterSimulation();
}


/// Set of officers that operate the submarine.
final class AICrew: AICrewTemp
{
	override @property string name() const { return m_name; }

	this(BOT_DIFFICULTY difficulty)
	{
		m_difficulty = difficulty;
		m_name = "BOT crew (" ~ difficulty.to!string ~ ")";
		m_state = new CrewState();
	}

	private
	{
		AICaptain m_captain;
		AIHelmsman m_helmsman;
		string m_name;
		BOT_DIFFICULTY m_difficulty;
		CrewState m_state;
		CrewGoal m_goal;
	}

	@property CrewGoal goal() { return m_goal; }

	// set new goal for a captain of the crew
	@property void goal(CrewGoal rhs)
	{
		m_goal = rhs;
		m_captain.captainOrder.pushBack(rhs);
	}

	@property CrewState state() { return m_state; }

	alias submarine = Captain.submarine;

	override @property void submarine(Submarine rhs)
	{
		super.submarine = rhs;
		// we need to build the officers according to submarine capabilities and
		// bot difficulty.
		m_captain = new AICaptain(this, m_difficulty);
		m_helmsman = new AIHelmsman(this, m_difficulty);
		trace("Building AICrew with ", m_difficulty, " difficulty");
	}

	override void afterSimulation()
	{
		if (m_submarine is null || m_submarine.dead)
			return;
		if (m_captain)
			m_captain.execute();
		if (m_helmsman)
			m_helmsman.execute();
	}
}


enum GoalStatus
{
	needAction,
	succeeded,
	failed
}

bool isFinalStatus(GoalStatus status)
{
	return status != GoalStatus.needAction;
}


/// The highest-order goal the crew can understand
abstract class CrewGoal
{
	this(AICrew crew)
	{
		m_crew = crew;
	}

	protected AICrew m_crew;

	final @property AICrew crew() { return m_crew; }

	@property GoalStatus status();
}


final class SwimToDestinationGoal: CrewGoal
{
	this(AICrew crew, vec2d dest)
	{
		super(crew);
		m_destination = dest;
	}

	private vec2d m_destination;
	@property vec2d destination() const { return m_destination; }

	override @property GoalStatus status()
	{
		vec2d subPos = crew.submarine.transform.wposition;
		double diff = (subPos - m_destination).length;
		if (diff < 200.0)
			return GoalStatus.succeeded;
		else
			return GoalStatus.needAction;
	}
}


struct OrderQueue(T)
{
	this(size_t queueSize)
	{
		m_queue = CircQueue!T(queueSize);
	}

	private CircQueue!T m_queue;

	@property bool hasOrder() const
	{
		return m_queue.length > 0;
	}

	T popFront()
	{
		T front = m_queue.front;
		m_queue.popFront();
		return front;
	}

	void pushBack(T order)
	{
		m_queue.pushBack(order);
	}
}


/// Strongly-typed CIC state, blackboard.
final class CrewState
{
}


// enum ContactRelation
// {
// 	unknown,
// 	neutral,
// 	enemy
// }

// enum ContactClass
// {
// 	unknown,
// 	weapon,
// 	vessel,
// 	decoy,
// 	environment
// }

// struct Solution
// {
// 	bool positionKnown;
// 	bool velocityKnown;
// 	usecs_t atTime;
// 	vec2d position;
// 	vec2d velocity;
// }

// /// CIC of bot crew tracks contacts
// struct Contact
// {
// 	Vessel vessel;
// 	ContactRelation relation;
// 	ContactClass classification;
// 	Solution solution;
// }


bool isCombatCapable(const Submarine sub)
{
	const SubmarineFactory subFac = Globals.entityDb.getSubmarineFactory(sub.prototypeName);
	return isCombatCapable(subFac);
}

bool isCombatCapable(const SubmarineFactory subFac)
{
	return subFac.tubeProtos.length > 0;
}


/**
Tactical commander that issues general orders to other bridge officers.
*/
final class AICaptain
{
	this(AICrew crew, BOT_DIFFICULTY difficulty)
	{
		m_crew = crew;
		m_difficulty = difficulty;
		m_ticksPerExecute = ticksPerDifficulty(m_difficulty);
		m_btRoot = buildEasyCaptainBt();
		captainOrder = OrderQueue!CrewGoal(1);
	}

	private
	{
		AICrew m_crew;
		BehavourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;

		CrewGoal m_activeGoal;
		HelmsmanOrderGoal m_helmsmansOrderGoal;
	}

	private enum HelmsmanOrderGoal: byte
	{
		unset,	/// there was no order given to helmsman
		obsolete,	/// last order, given to helmsman, is not about current captain goal
		sync	/// helmsman's order is in sync with captain's order
	}

	/// orders are to be put here
	OrderQueue!CrewGoal captainOrder;

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
	}

	private final class ProcessNewOrder: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Consume new crew order", 500, file, line);
		}

		override ExecutionResult onTicksConsumed()
		{
			trace("ProcessNewOrder onTicksConsumed");
			if (!captainOrder.hasOrder)
				return ExecutionResult.failure;
			m_activeGoal = captainOrder.popFront();
			trace("Captain received new goal: ", m_activeGoal.toString);
			if (m_helmsmansOrderGoal != HelmsmanOrderGoal.unset)
				m_helmsmansOrderGoal = HelmsmanOrderGoal.obsolete;
			return ExecutionResult.success;
		}
	}

	private final class OrderHelmsmanToSwimToDest: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Give commands to helmsman to arrive at destination", 400,
				file, line);
		}

		override ExecutionResult onTicksConsumed()
		{
			SwimToDestinationGoal goal = cast(SwimToDestinationGoal) m_activeGoal;
			assert(goal);
			trace("Ordering helmsman to swim to destination");
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.destination;
			whereToSwim.destination = goal.destination;
			m_crew.m_helmsman.whereToSwimOrder.pushBack(whereToSwim);
			m_crew.m_helmsman.navigationSpeedOrder.pushBack(NavigationSpeed.random);
			m_helmsmansOrderGoal = HelmsmanOrderGoal.sync;
			return ExecutionResult.success;
		}
	}

	private BehavourTreeNode orderExecutionTree()
	{
		FallbackNode fb = new FallbackNode("for different orders...", [
			new SequenceNode("For destination order give command to helmsman", [
				new ConditionNode("Is order a destination order?", () =>
					cast(SwimToDestinationGoal) m_activeGoal !is null),
				new ConditionNode("Helmsman order out of sync?", () =>
					m_helmsmansOrderGoal != HelmsmanOrderGoal.sync),
				new OrderHelmsmanToSwimToDest()
			])
		]);
		return fb;
	}

	private BehavourTreeNode buildEasyCaptainBt()
	{
		BehavourTreeNode[] rootFallbackNodes;
		// if (m_crew.submarine.isCombatCapable)
		// {
		// 	rootFallbackNodes ~= new SequenceNode("Attack if target visible", [
		// 		new ConditionNode("Have ammo", null),
		// 		new ConditionNode("Any target visible and solution ready", null),
		// 		new FallbackNode("Approach and attack closest target", [
		// 				new SequenceNode("Approach target if needed", [
		// 					new ConditionNode("Closest target too far"),
		// 					new NopAction("Approach closest target")
		// 				]),
		// 				new NopAction("Attack closest target")
		// 			]),
		// 		]);
		// }
		rootFallbackNodes ~= [
			new SequenceNode("Process new order", [
				new ConditionNode("New order present", () => captainOrder.hasOrder),
				new ProcessNewOrder()
				]),
			orderExecutionTree()
		];
		BehavourTreeNode res = new FallbackNode("Easy captain AI", rootFallbackNodes);
		return res;
	}
}