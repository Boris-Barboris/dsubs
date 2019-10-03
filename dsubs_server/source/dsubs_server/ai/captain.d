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



/**
Set of officers that operate the submarine.
*/
final class AICrew: Captain
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
		CaptainGoal m_goal;
	}

	@property CaptainGoal goal() { return m_goal; }

	// set new goal for a captain of the crew
	@property void goal(CaptainGoal rhs)
	{
		m_goal = rhs;
		m_state.captainOrder.pushBack(rhs);
	}

	@property CrewState state() { return m_state; }

	override @property void submarine(Submarine rhs)
	{
		super(rhs);
		// we need to build the officers according to submarine capabilities and
		// bot difficulty.
		m_captain = new AICaptain(this, m_difficulty);
		m_helmsman = new AIHelmsman(this, m_difficulty);
	}

	void afterSimulation()
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


abstract class CaptainGoal
{
	this(AICaptain captain)
	{
		m_captain = captain;
	}

	protected AICaptain m_captain;

	final @property AICaptain captain() { return m_captain; }

	@property GoalStatus status();
}


final class SwimToDestinationGoal: CaptainGoal
{
	this(AICaptain captain, vec2d dest)
	{
		super(captain);
		m_destination = dest;
	}

	private vec2d m_destination;
	@property vec2d destination() const { return m_destination; }

	override @property GoalStatus status()
	{
		vec2d subPos = m_captain.crew.submarine.transform.wposition;
		double diff = (subPos - m_destination).length;
		if (diff < 200.0)
			return GoalStatus.succeeded;
		else
			return GoalStatus.needAction;
	}
}


struct OrderQueue!(T)
{
	this(size_t queueSize)
	{
		m_queue = CircQueue!T(queueSize);
	}

	private CircQueue!T m_queue;

	@property bool hasOrders() const
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


/// Strongly-typed blackboard
final class CrewState
{
	this()
	{
		helmsmanOrder = OrderQueue!HelmsmanOrder(1);
		captainOrder = OrderQueue!CaptainGoal(1);
	}

	OrderQueue!CaptainGoal captainOrder;
	OrderQueue!HelmsmanOrder helmsmanOrder;
}

enum ContactRelation
{
	unknown,
	neutral,
	enemy
}

enum ContactClass
{
	unknown,
	weapon,
	vessel,
	decoy,
	environment
}

struct Solution
{
	bool positionKnown;
	bool velocityKnown;
	usecs_t atTime;
	vec2d position;
	vec2d velocity;
}

/// CIC of bot crew tracks contacts
struct Contact
{
	Vessel vessel;
	ContactRelation relation;
	ContactClass classification;
	Solution solution;
}


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
	}

	private
	{
		AICrew m_crew;
		BehavourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;
	}

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
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
			new SequenceNode("Proceed to destination", [
				new ConditionNode("Destination defined", null),
				new NopAction("Swim to destination")
				]),
			new NopAction("Idle")
		];
		BehavourTreeNode res = new FallbackNode("Easy captain AI", rootFallbackNodes, true);
		return res;
	}
}