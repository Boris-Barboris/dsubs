module dsubs_server.ai.captain;

import std.algorithm;
import std.array: array;

import dsubs_common.containers.circqueue;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.weaponry;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.ai.common;
import dsubs_server.ai.helmsman;
import dsubs_server.ai.acoustic;

public import dsubs_server.ai.common: BOT_DIFFICULTY;


/// temporary interface in order to not break default BR scenario
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
		AIAcoustic m_acoustic;
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
		if (isCombatCapable(rhs))
		{
			m_acoustic = new AIAcoustic(this, m_difficulty);
			m_acoustic.prepareSensors();
		}
	}

	override void afterSimulation()
	{
		if (m_submarine is null || m_submarine.dead)
			return;
		if (m_captain)
			m_captain.execute();
		if (m_helmsman)
			m_helmsman.execute();
		if (m_acoustic)
			m_acoustic.execute();
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
	Contact*[Vessel] contacts;
}


enum ContactRelation
{
	unknown,
	ally,
	neutral,
	enemy
}

enum ContactClass
{
	unknown,
	weapon,
	submarine,
	decoy
}

struct Solution
{
	bool set;
	usecs_t atTime;
	bool positionKnown;
	vec2d position;
	vec2d velocity = vec2d(0, 0);

	vec2d extrapolatedPos(usecs_t timePoint)
	{
		assert(positionKnown);
		return position + velocity * (timePoint - atTime) / 1e6f;
	}
}

/// CIC of bot crew tracks contacts
struct Contact
{
	Vessel vessel;
	usecs_t createdAt;
	ContactRelation relation;		// implies that captains do not switch sides
	ContactClass classification;
	Solution solution;
	usecs_t lastHydrophoneData;
	usecs_t lastActiveSonarData;
	// Counters that abstract away contact and TMA quality.
	float passiveSonarPoints = 0.0f;
	float activeSonarPoints = 0.0f;

	/// Age in seconds
	@property float age() const
	{
		return (Globals.sim.worldTime - createdAt) / 1000_000L;
	}

	@property float hydrophoneDataAge() const
	{
		return (Globals.sim.worldTime - lastHydrophoneData) / 1000_000L;
	}

	@property float activeSonarDataAge() const
	{
		return (Globals.sim.worldTime - lastActiveSonarData) / 1000_000L;
	}
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
		desync,	/// last order, given to helmsman, is not about current captain goal,
				/// or is simply obsolete
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

		override @property bool shouldBeRunning()
		{
			return captainOrder.hasOrder;
		}

		override ExecutionResult onTicksConsumed()
		{
			trace("ProcessNewOrder onTicksConsumed");
			if (!captainOrder.hasOrder)
				return ExecutionResult.failure;
			m_activeGoal = captainOrder.popFront();
			trace("Captain received new goal: ", m_activeGoal.toString);
			if (m_helmsmansOrderGoal != HelmsmanOrderGoal.unset)
				m_helmsmansOrderGoal = HelmsmanOrderGoal.desync;
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

		override @property bool shouldBeRunning()
		{
			return cast(SwimToDestinationGoal) m_activeGoal !is null &&
				m_helmsmansOrderGoal != HelmsmanOrderGoal.sync;
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
			new OrderHelmsmanToSwimToDest()
		]);
		return fb;
	}

	private
	{
		// target, chosen as main
		Vessel m_mainTarget;
		CombatNavigationState m_combatNavState;
		usecs_t m_lastFire;

		enum CombatNavigationState: ubyte
		{
			none,
			approachMainTarget,
			tacticalFloat
		}
	}

	private final class UpdateSolutions: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			// 30 seconds for solutions update for an easy bot
			super("Perform TMA for all important contacts", 3000, file, line);
		}

		override ExecutionResult onTicksConsumed()
		{
			// loop over all contacts and update their solutions
			Vessel[] contactsToRemove;
			foreach (vesselCtcPair; m_crew.state.contacts.byKeyValue)
			{
				Contact* ctc = vesselCtcPair.value;
				if (ctc.vessel.dead)
				{
					// we should drop dead contacts
					contactsToRemove ~= ctc.vessel;
					continue;
				}
				// do not update solutions too often
				if (Globals.sim.worldTime - ctc.solution.atTime < SOLUTION_CONST_PERIOD)
					continue;
				updateContactSolution(ctc);
			}
			foreach (Vessel v; contactsToRemove)
				m_crew.state.contacts.remove(v);
			return ExecutionResult.success;
		}

		/// How quickly the contact score drops with passive sonar data age.
		enum float PASSIVE_DECAY_SQR_K = 0.05f;
		/// How quickly the contact score drops with active sonar data age.
		enum float ACTIVE_DECAY_SQR_K = 0.01f;
		/// score penalty for unclassified contact
		enum float UNCLASSIFIED_MULT = 0.05f;
		/// Min score at wich we start to estimate contact position just from
		/// ray data samples.
		enum float POSITION_ESTIMATE_MIN_SCORE = 100.0f;
		/// minimum pause between solution updates.
		enum usecs_t SOLUTION_CONST_PERIOD = 10_000_000L;
		/// gain for balancing positional error
		enum float POS_ERROR_SCORE_RATIO = 5.0f;
		/// gain for balancing velocity error
		enum float VEL_ERROR_SCORE_RATIO = 5.0f;

		private void updateContactSolution(Contact* ctc)
		{
			// first we need to cap points in order to prevent overflow
			ctc.passiveSonarPoints = min(ctc.passiveSonarPoints, 1e5f);
			ctc.activeSonarPoints = min(ctc.activeSonarPoints, 1e5f);
			// next we estimate universal contact score that we use to
			// comare with contacts and set position/direction error.
			float score = 0.0f;
			// is there any positional data in the list of data samples?
			bool hardPosData = false;
			if (ctc.lastHydrophoneData)
			{
				score += ctc.passiveSonarPoints /
					PASSIVE_DECAY_SQR_K / pow(ctc.hydrophoneDataAge, 2);
			}
			if (ctc.lastActiveSonarData)
			{
				hardPosData = true;
				score += ctc.activeSonarPoints /
					ACTIVE_DECAY_SQR_K / pow(ctc.activeSonarDataAge, 2);
			}
			if (ctc.classification == ContactClass.unknown)
				score *= UNCLASSIFIED_MULT;
			trace("score: ", score);
			if (hardPosData || score >= POSITION_ESTIMATE_MIN_SCORE)
			{
				// we have enough data to estimate position and speed
				vec2d posDiff = ctc.vessel.transform.wposition -
					m_crew.submarine.transform.wposition;
				double posError = posDiff.length * POS_ERROR_SCORE_RATIO / sqrt(score);
				double trueVel = ctc.vessel.rigidBody.kinet.velLength;
				double velError = trueVel * VEL_ERROR_SCORE_RATIO / sqrt(score);
				trace("Assigning position-rich solution to contact with score ", score,
					", posError ", posError, ", velError ", velError,
					" at age ", ctc.age(), " seconds");
				ctc.solution.positionKnown = true;
				ctc.solution.position = ctc.vessel.transform.wposition +
					posError * courseVector(uniform(0, 2 * PI));
				ctc.solution.velocity = trueVel +
					velError * courseVector(uniform(0, 2 * PI));
				ctc.solution.atTime = Globals.sim.worldTime;
				ctc.solution.set = true;
			}
		}
	}

	private final class ChooseClosestEnemyContact: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Choose the closest enemy submarine with known " ~
				"position as main target", 300, file, line);
		}

		override ExecutionResult onTicksConsumed()
		{
			static struct VesselAndRange
			{
				Vessel v;
				double range;
			}

			vec2d curPos = m_crew.submarine.transform.wposition;
			VesselAndRange[] enemyVessels = m_crew.state.contacts.byValue.filter!(
				c =>
					c.relation == ContactRelation.enemy &&
					c.classification == ContactClass.submarine &&
					c.solution.positionKnown).
				map!(c => VesselAndRange(
					c.vessel, (c.solution.position - curPos).length)).array;
			if (enemyVessels.length == 0)
				return ExecutionResult.failure;
			enemyVessels.sort!((a, b) => a.range < b.range);
			m_mainTarget = enemyVessels[0].v;
			trace("Choosing closest target ", enemyVessels[0], " as main");
			return ExecutionResult.success;
		}
	}

	private BehavourTreeNode easyAttackTargetTree()
	{
		FallbackNode fb = new FallbackNode("simple attack pattern", [
			new SequenceNode("sequence of actions for known target", [
				new ConditionNode("if we have main target", () => m_mainTarget !is null),
				new FallbackNode("when we have main target", [
					new NopAction("drop target if it's dead or too old"),
					new SequenceNode("Shoot torpedo", [
						new NopAction("Swim closer to target if needed"),
						new NopAction("Maintain tactical speed and point nose " ~
							"onto the target"),
						new ConditionNode("Haven't fired in the last 60 seconds", () =>
							Globals.sim.worldTime - m_lastFire > 60_000_000L),
						new NopAction("Ensure we have a loaded tube"),
						new NopAction("Fire the tube onto the main target's solution")
					])
				])
			]),
			new ChooseClosestEnemyContact()
		]);
		return fb;
	}

	private BehavourTreeNode buildEasyCaptainBt()
	{
		BehavourTreeNode[] rootParallelNodes;
		rootParallelNodes ~= [
			new ProcessNewOrder(),
			// new ParallelNode("Dedicate time to both TMA and attacking the target", [,
			// 	//easyAttackTargetTree(),
			// ]),
			orderExecutionTree()
		];
		rootParallelNodes ~= new UpdateSolutions();
		BehavourTreeNode res = new ParallelNode("Easy captain AI", rootParallelNodes);
		return res;
	}
}