module dsubs_server.ai.captain;

import std.algorithm: any, filter, map, sort, startsWith;
import std.array: array;

import dsubs_common.containers.circqueue;
import dsubs_common.math;
import dsubs_common.api.entities;

import dsubs_sound.activesonar;

import dsubs_server.acoustics: AcousticEnv;
import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.weaponry;
import dsubs_server.torpedo;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.simulator;
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

	@property Simulator simulator()
	{
		if (submarine)
			return submarine.simulator;
		return null;
	}

	@property BOT_DIFFICULTY difficulty() const { return m_difficulty; }

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
		m_queue = CircQueue!(T, true)(queueSize);
	}

	private CircQueue!(T, true) m_queue;

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

	vec2d extrapolatedPos(usecs_t timePoint) const
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

	private
	{
		usecs_t m_lastHydrophoneData;
		usecs_t m_lastActiveSonarData;
	}

	@property usecs_t lastHydrophoneData() const { return m_lastHydrophoneData; }

	@property void lastHydrophoneData(usecs_t rhs)
	{
		m_lastHydrophoneData = max(m_lastHydrophoneData, rhs);
		if (rhs > lastData)
		{
			lastData = rhs;
			updateTrueParams();
		}
	}

	@property usecs_t lastActiveSonarData() const { return m_lastActiveSonarData; }

	@property void lastActiveSonarData(usecs_t rhs)
	{
		m_lastActiveSonarData = max(m_lastActiveSonarData, rhs);
		if (rhs > lastData)
		{
			lastData = rhs;
			updateTrueParams();
		}
	}

	private void updateTrueParams()
	{
		lastDataTruePosition = vessel.transform.wposition;
		lastDataTrueVelocity = vessel.rigidBody.kinet.vel;
	}

	usecs_t lastData;
	// true vessel's position and velocity at the time the last sample was recorded
	vec2d lastDataTruePosition;
	vec2d lastDataTrueVelocity;

	// Counters that abstract away contact and TMA quality.
	float passiveSonarPoints = 0.0f;
	float activeSonarPoints = 0.0f;

	/// Age in seconds
	@property float age() const
	{
		return (vessel.simulator.worldTime - createdAt) / 1000_000L;
	}

	/// Solution age in seconds
	@property float solutionAge() const
	{
		assert(solution.set);
		return (vessel.simulator.worldTime - solution.atTime) / 1000_000L;
	}

	// 1.0f + is to prevent division by zero

	@property float hydrophoneDataAge() const
	{
		return 1.0f + (vessel.simulator.worldTime - m_lastHydrophoneData) / 1000_000L;
	}

	@property float activeSonarDataAge() const
	{
		return 1.0f + (vessel.simulator.worldTime - m_lastActiveSonarData) / 1000_000L;
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

bool hasActiveSonar(Submarine sub)
{
	return sub.sonar !is null;
}

double effectiveFiringRange(Submarine sub, const Solution tgt)
{
	// FIXME
	float maxTorpRange = 8000.0f;
	float medianTorpSpd = 25.0f;
	float time = maxTorpRange / medianTorpSpd;
	// we need a very simple, imprecise formula
	vec2d deltaPos = tgt.extrapolatedPos(sub.simulator.worldTime) - sub.transform.wposition;
	double dotVelValue = dot(tgt.velocity, deltaPos.normalizedz);
	double effVel = clamp(medianTorpSpd - dotVelValue, 2.0f, 2 * medianTorpSpd);
	double effRange = time * effVel;
	return effRange;
}

/// Returns true if the weapon is a torpedo.
bool isTorpedoName(string weaponName)
{
	return (cast(TorpedoFactory) Globals.entityDb.getWeaponFactory(weaponName)) !is null;
}

/// Returns true if the is at least one torpedo in ammo racks or in the tubes
bool haveTorpedoes(const Submarine sub)
{
	if (sub.getAmmoRoom(0).weaponCount > 0)
		return true;
	if (sub.tubeRange.any!(t => t.loadedWeapon && isTorpedoName(t.loadedWeapon)))
		return true;
	return false;
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
		final switch (m_difficulty)
		{
			case (BOT_DIFFICULTY.easy):
				m_btRoot = buildEasyCaptainBt();
				break;
			case (BOT_DIFFICULTY.medium):
				m_btRoot = buildMediumCaptainBt();
				break;
			case (BOT_DIFFICULTY.hard):
				m_btRoot = buildMediumCaptainBt();
				break;
		}
		captainOrder = OrderQueue!CrewGoal(1);
	}

	pragma(inline) @property Simulator simulator() { return m_crew.simulator; }

	private
	{
		AICrew m_crew;
		BehaviourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;

		CrewGoal m_activeGoal;
		HelmsmanOrderGoal m_helmsmansOrderGoal;
		usecs_t m_lastOrderToHelmsman;
	}

	private @property bool helmsmanOrderOnCooldown()
	{
		return (simulator.worldTime - m_lastOrderToHelmsman) < 15_000_000L;
	}

	private void giveOrdersToHelmsman(WhereToSwim whereToSwim, NavigationSpeed navSpeed,
		HelmsmanOrderGoal goal)
	{
		// trace(m_crew.submarine, " giving order to helmsman ", goal);
		m_crew.m_helmsman.whereToSwimOrder.pushBack(whereToSwim);
		m_crew.m_helmsman.navigationSpeedOrder.pushBack(navSpeed);
		m_helmsmansOrderGoal = goal;
		m_lastOrderToHelmsman = simulator.worldTime;
	}

	private enum HelmsmanOrderGoal: byte
	{
		unset,		/// there was no order given to helmsman
		attack,		/// last order, given to helmsman, is not about current captain goal,
					/// but about attack.
		defense,	/// evasion order.
		sync,		/// helmsman's order is in sync with captain's order
		desync		/// helmsman's order is for some previous captain order
	}

	/// orders are to be put here
	OrderQueue!CrewGoal captainOrder;

	static float maxTorpedoBudgetForDifficulty(BOT_DIFFICULTY diff)
	{
		final switch (diff)
		{
			case BOT_DIFFICULTY.easy:
				return 200.0f;
			case BOT_DIFFICULTY.medium:
				return 300.0f;
			case BOT_DIFFICULTY.hard:
				return 400.0f;
		}
	}

	static float torpedoBudgetRegenPerSecDifficulty(BOT_DIFFICULTY diff)
	{
		final switch (diff)
		{
			case BOT_DIFFICULTY.easy:
				return 0.3f;
			case BOT_DIFFICULTY.medium:
				return 0.6f;
			case BOT_DIFFICULTY.hard:
				return 1.0f;
		}
	}

	void execute()
	{
		int ticks = m_ticksPerExecute;
		// every second we increase budget
		m_torpedoBudget = fmin(m_torpedoBudget +
			torpedoBudgetRegenPerSecDifficulty(m_difficulty),
			maxTorpedoBudgetForDifficulty(m_difficulty));
		m_btRoot.execute(ticks);
	}

	private final class ProcessNewOrder: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Consume new crew order", 500, false, file, line);
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
			if (m_helmsmansOrderGoal == HelmsmanOrderGoal.sync)
				m_helmsmansOrderGoal = HelmsmanOrderGoal.desync;
			return ExecutionResult.success;
		}
	}

	private final class OrderHelmsmanToSwimToDest: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Give commands to helmsman to arrive at destination", 400,
				false, file, line);
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
			// trace("Ordering helmsman to swim to destination");
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.destination;
			whereToSwim.destination = goal.destination;
			NavigationSpeed speed = isCombatCapable(m_crew.submarine) ?
				NavigationSpeed.tactical : NavigationSpeed.random;
			giveOrdersToHelmsman(whereToSwim, speed, HelmsmanOrderGoal.sync);
			return ExecutionResult.success;
		}
	}

	private final class IdleState: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Give commands to helmsman to idle", 400,
				false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			return m_activeGoal is null && m_helmsmansOrderGoal != HelmsmanOrderGoal.sync;
		}

		override ExecutionResult onTicksConsumed()
		{
			trace("Ordering helmsman to idle");
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.idle;
			giveOrdersToHelmsman(whereToSwim, NavigationSpeed.stop,
				HelmsmanOrderGoal.sync);
			return ExecutionResult.success;
		}
	}

	private BehaviourTreeNode orderExecutionTree()
	{
		FallbackNode fb = new FallbackNode("for different orders...", [
			new OrderHelmsmanToSwimToDest(),
			new IdleState()
		]);
		return fb;
	}

	private
	{
		// target, chosen as main
		Vessel m_mainTarget;
		// torpedo we are currently dodging
		Torpedo m_mainDanger;
		usecs_t m_lastFire;
		usecs_t m_lastDecoyFire;
		usecs_t m_lastPing;

		/// burst limiter to reduce torpedo spam.
		float m_torpedoBudget = 150.0f;
	}

	@property bool torpedoBudgetOk() const { return m_torpedoBudget >= 100.0f; }

	@property Contact* mainContact()
	{
		return m_crew.state.contacts[m_mainTarget];
	}

	@property Contact* mainDanger()
	{
		return m_crew.state.contacts[m_mainDanger];
	}

	double rangeFromContact(Contact* ctc)
	{
		return (ctc.solution.extrapolatedPos(simulator.worldTime) -
			m_crew.submarine.transform.wposition).length;
	}

	private final class UpdateSolutions: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			// 30 seconds for solutions update for an easy bot
			super("Perform TMA for all important contacts", 3000, false, file, line);
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
					if (m_mainDanger is ctc.vessel)
						m_mainDanger = null;
					if (m_mainTarget is ctc.vessel)
						m_mainTarget = null;
					continue;
				}
				// do not update solutions too often
				if (simulator.worldTime - ctc.solution.atTime < SOLUTION_CONST_PERIOD)
					continue;
				// do not update solution if no new data has arrived
				if (ctc.solution.atTime >= ctc.lastData)
					continue;
				// do not update solution for friends
				if (ctc.relation == ContactRelation.ally)
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
		enum float ACTIVE_DECAY_SQR_K = 0.005f;
		/// score penalty for unclassified contact
		enum float UNCLASSIFIED_MULT = 0.05f;
		/// Min score at wich we start to estimate contact position just from
		/// ray data samples.
		enum float POSITION_ESTIMATE_MIN_SCORE = 100.0f;
		/// minimum interval between solution updates.
		enum usecs_t SOLUTION_CONST_PERIOD = 10_000_000L;
		/// gain for balancing positional error
		enum float POS_ERROR_SCORE_RATIO = 4.0f;
		/// gain for balancing velocity error
		enum float VEL_ERROR_SCORE_RATIO = 6.0f;

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
			assert(isNormal(score));
			// trace("score: ", score);
			if (hardPosData || score >= POSITION_ESTIMATE_MIN_SCORE)
			{
				// we have enough data to estimate position and speed
				vec2d posDiff = ctc.lastDataTruePosition -
					m_crew.submarine.transform.wposition;
				double maxPosError = posDiff.length * POS_ERROR_SCORE_RATIO / sqrt(score);
				vec2d trueVel = ctc.lastDataTrueVelocity;
				double maxVelError = trueVel.length * VEL_ERROR_SCORE_RATIO / sqrt(score);
				if (!ctc.solution.positionKnown)
				{
					trace("Assigning first position-rich solution to contact ", *ctc,
						" with score ",
						score, ", maxPosError ", maxPosError, ", maxVelError ", maxVelError,
						" at age ", ctc.age(), " seconds");
				}
				ctc.solution.positionKnown = true;
				ctc.solution.position = ctc.lastDataTruePosition +
					uniform!"[]"(0.0f, maxPosError) * courseVector(uniform(0, 2 * PI));
				ctc.solution.velocity = trueVel +
					uniform!"[]"(0.0f, maxVelError) * courseVector(uniform(0, 2 * PI));
				ctc.solution.atTime = ctc.lastData;
				ctc.solution.set = true;
			}
		}
	}

	private final class ChooseClosestEnemyContact: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Choose the closest enemy submarine with known " ~
				"position as the new main target", 300, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			return m_crew.state.contacts.byValue.any!(
				c =>
					c.relation == ContactRelation.enemy &&
					c.classification == ContactClass.submarine &&
					c.solution.positionKnown);
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
					c.vessel, (c.solution.extrapolatedPos(simulator.worldTime) - curPos).length)).array;
			if (enemyVessels.length == 0)
				return ExecutionResult.failure;
			enemyVessels.sort!((a, b) => a.range < b.range);
			m_mainTarget = enemyVessels[0].v;
			trace("Choosing closest target ", m_mainTarget, " as main");
			return ExecutionResult.success;
		}
	}

	private final class EvadeMainDangerIfNeededTangent: FixedCostActionNode
	{
		this(NavigationSpeed speed, string file = __FILE__, size_t line = __LINE__)
		{
			super("If there is main danger, evade it", 600, false, file, line);
			m_evasionSpeed = speed;
		}

		private NavigationSpeed m_evasionSpeed;

		override @property bool shouldBeRunning()
		{
			invertShouldBeRunning = false;
			if (m_mainDanger is null)
				return false;
			// if we're already defending, helmsman's cooldown should not
			// cause Failure, but success.
			invertShouldBeRunning = m_helmsmansOrderGoal == HelmsmanOrderGoal.defense;
			return !helmsmanOrderOnCooldown || !invertShouldBeRunning;
		}

		private vec2d getEvasionDirection()
		{
			Solution torpSol = mainDanger.solution;
			vec2d relPos = torpSol.extrapolatedPos(simulator.worldTime) - m_crew.submarine.transform.wposition;
			// we do not account for our speed here
			vec2d evadeVector = vec2d(torpSol.velocity.y, -torpSol.velocity.x);
			if (dot(evadeVector, relPos) >= 0.0)
				evadeVector = -evadeVector;
			return evadeVector;
		}

		override ExecutionResult onTicksConsumed()
		{
			double evasionCourse = courseAngle(getEvasionDirection());
			WhereToSwim wts;
			wts.type = WhereToSwimType.course;
			wts.course = evasionCourse;
			giveOrdersToHelmsman(wts, m_evasionSpeed, HelmsmanOrderGoal.defense);
			return ExecutionResult.success;
		}
	}

	private final class ChooseMostDangerousTorp: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Choose the most dangerous enemy torpedo with known " ~
				"position as the new main danger", 600, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			return m_mainDanger !is null ||
			m_crew.state.contacts.byValue.any!(
				c =>
					c.classification == ContactClass.weapon &&
					c.solution.positionKnown &&
					c.solutionAge < MAX_SOLUTION_AGE);
		}

		enum double MIN_MISS_WORRY = 1000.0;
		enum float MAX_SOLUTION_AGE = 75.0f;

		private double getDanger(Solution torpSol)
		{
			assert(torpSol.set);
			assert(torpSol.positionKnown);
			vec2d relVel = torpSol.velocity - m_crew.submarine.rigidBody.kinet.vel;
			vec2d relPos = torpSol.extrapolatedPos(simulator.worldTime) - m_crew.submarine.transform.wposition;
			// if torp swims perfectly on us, relVel is parallel to -relPos.
			if (dot(relVel.normalizedz, relPos.normalizedz) >= 0.0)
				return 0.0;
			double angle = angleBetween(relVel, relPos);
			double totalMiss = relPos.length * sin(angle).fabs;
			// trace(m_crew.submarine, " totalMiss: ", totalMiss);
			if (totalMiss > MIN_MISS_WORRY)
				return 0.0;
			assert(!isNaN(totalMiss));
			totalMiss = max(1.0, totalMiss);
			// 1e3 just for scale
			return 1e3 / totalMiss / max(1.0, relPos.length);
		}

		override ExecutionResult onTicksConsumed()
		{
			static struct VesselAndDanger
			{
				Vessel v;
				double danger;
			}

			vec2d curPos = m_crew.submarine.transform.wposition;
			VesselAndDanger[] dangers = m_crew.state.contacts.byValue.filter!(
				c =>
					c.classification == ContactClass.weapon &&
					c.solution.positionKnown &&
					c.solutionAge < MAX_SOLUTION_AGE).
				map!(c => VesselAndDanger(
					c.vessel, getDanger(c.solution))).array;
			if (dangers.length == 0)
			{
				m_mainDanger = null;
				return ExecutionResult.failure;
			}
			dangers.sort!((a, b) => a.danger < b.danger);
			if (dangers[$-1].danger == 0.0)
			{
				// trace("AI resets main danger because most dangerous is not relevant");
				m_mainDanger = null;
				return ExecutionResult.failure;
			}
			if (m_mainDanger !is dangers[$-1].v)
			{
				m_mainDanger = cast(Torpedo) dangers[$-1].v;
				assert(m_mainDanger !is null, "unexpected non-torpedo as danger");
				trace("Choosing ", m_mainDanger, " as main danger");
			}
			else if (m_mainDanger && mainDanger.solutionAge > MAX_SOLUTION_AGE)
			{
				m_mainDanger = null;
				trace("AI resets main danger because of solution age");
				return ExecutionResult.failure;
			}
			return ExecutionResult.success;
		}
	}

	private final class DropStaleMainTarget: ActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Drop dead or very old main target", file, line);
		}

		/// For this many seconds we will keep the contact alive
		enum float MAX_SOLUTION_AGE_SEC = 600.0f;

		override ExecutionResult execute(ref int ticks)
		{
			if (m_mainTarget is null)
				return ExecutionResult.failure;
			Contact* ctc = m_crew.state.contacts[m_mainTarget];
			if (m_mainTarget.dead || ctc.solutionAge > MAX_SOLUTION_AGE_SEC)
			{
				trace(m_crew.submarine, " dropping main target ", m_mainTarget);
				m_crew.state.contacts.remove(m_mainTarget);
				m_mainTarget = null;
				return ExecutionResult.success;
			}
			return ExecutionResult.failure;
		}
	}

	private final class EnsureTorpedoesLoading: FixedCostActionNode
	{
		this(bool invert, string file = __FILE__, size_t line = __LINE__)
		{
			super("Initiate torpedoes loading into free tubes", 400, invert, file, line);
		}

		override @property bool shouldBeRunning()
		{
			// FIXME
			bool haveMinogaInRacks = m_crew.submarine.ammoRoomRange.any!(ar =>
				ar.getWeaponCount("Minoga") > 0);
			auto tubes = m_crew.submarine.tubeRange;
			return haveMinogaInRacks && tubes.any!(t =>
				t.state == TubeState.dry &&
				t.type == TubeType.standard &&
				t.loadedWeapon == null);
		}

		override ExecutionResult onTicksConsumed()
		{
			foreach (Tube tube; m_crew.submarine.tubeRange)
			{
				if (tube.state == TubeState.dry &&
					tube.type == TubeType.standard &&
					tube.loadedWeapon == null)
				{
					trace("AI captain requesting tube load for tube ", tube.id);
					TubeOperationResult res = tube.processLoadRequest("Minoga");
				}
			}
			return ExecutionResult.success;
		}
	}

	private final class EnsureDecoysLoading: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Initiate decoy loading into free tubes", 400, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			// FIXME: room number.
			AmmoRoom room = m_crew.submarine.getAmmoRoom(1);
			if (room.getWeaponCount("Decoy(active)") == 0 &&
				room.getWeaponCount("Decoy(passive)") == 0)
				return false;
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
				t.state == TubeState.dry &&
				t.type == TubeType.decoy &&
				t.loadedWeapon == null);
		}

		private string selectDecoyWeHaveMost()
		{
			// FIXME: shitty selection
			AmmoRoom room = m_crew.submarine.getAmmoRoom(1);
			int passiveCount = room.getWeaponCount("Decoy(passive)");
			int activeCount = room.getWeaponCount("Decoy(active)");
			if (passiveCount > activeCount)
				return "Decoy(passive)";
			else
				return "Decoy(active)";
		}

		override ExecutionResult onTicksConsumed()
		{
			foreach (Tube tube; m_crew.submarine.tubeRange)
			{
				if (tube.state == TubeState.dry &&
					tube.type == TubeType.decoy &&
					tube.loadedWeapon == null)
				{
					trace("AI captain requesting decoy tube load for tube ", tube.id);
					TubeOperationResult res = tube.processLoadRequest(
						selectDecoyWeHaveMost());
					assert(res.tubeChanged);
				}
			}
			return ExecutionResult.success;
		}
	}

	private final class EnsureDecoyTubesOpening: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Loaded decoy tubes must be opened", 400, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
				t.desiredState != TubeState.open &&
				t.state == TubeState.dry &&
				t.type == TubeType.decoy &&
				t.loadedWeapon.startsWith("Decoy"));
		}

		override ExecutionResult onTicksConsumed()
		{
			foreach (Tube tube; m_crew.submarine.tubeRange)
			{
				if (tube.desiredState != TubeState.open &&
					tube.state == TubeState.dry &&
					tube.type == TubeType.decoy &&
					tube.loadedWeapon != null)
				{
					trace("AI captain requesting decoy tube open for tube ", tube.id);
					tube.processStateRequest(TubeState.open);
				}
			}
			return ExecutionResult.success;
		}
	}

	/// Very stupid node that always turns towards the target and always swims
	private final class SwimCloserToMainTarget: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Approach main target until the distance is right", 500,
				false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			return m_mainTarget !is null;
		}

		override ExecutionResult onTicksConsumed()
		{
			if (helmsmanOrderOnCooldown && m_helmsmansOrderGoal == HelmsmanOrderGoal.attack)
				return ExecutionResult.success;
			double firingRange = effectiveFiringRange(
				m_crew.submarine, mainContact.solution);
			vec2d posDiff = mainContact.solution.extrapolatedPos(simulator.worldTime) -
				m_crew.submarine.transform.wposition;
			double currentRange = posDiff.length;
			bool needToSwimFast;
			// speed up to turn our nose
			if (dgr2rad(60.0) < angleDist(
				courseAngle(posDiff), m_crew.submarine.transform.wrotation).fabs)
				needToSwimFast = true;
			// speed up to approach
			if (currentRange > firingRange * 0.8)
				needToSwimFast = true;
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.destination;
			whereToSwim.destination = mainContact.solution.extrapolatedPos(simulator.worldTime);
			NavigationSpeed speed = needToSwimFast ?
				NavigationSpeed.tactical : NavigationSpeed.silent;
			giveOrdersToHelmsman(whereToSwim, speed, HelmsmanOrderGoal.attack);
			return ExecutionResult.success;
		}
	}


	/// A bit smarter approach/keep at range behaviour.
	private final class KeepDistanceFromMainTarget: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Approach main target until the distance is right", 500,
				false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			return m_mainTarget !is null;
		}

		override ExecutionResult onTicksConsumed()
		{
			if (helmsmanOrderOnCooldown && m_helmsmansOrderGoal == HelmsmanOrderGoal.attack)
				return ExecutionResult.success;
			double firingRange = effectiveFiringRange(
				m_crew.submarine, mainContact.solution);
			vec2d curTgtPos = mainContact.solution.extrapolatedPos(simulator.worldTime);
			vec2d posDiff = curTgtPos - m_crew.submarine.transform.wposition;
			double currentRange = posDiff.length;
			bool needToTurnNose, needToSwimFast;
			bool needToBoost;
			// we do not turn if towed array is used
			if (!m_crew.m_acoustic.isTowedArraysUsed)
			{
				float noseAngleToTgt = angleDist(
					courseAngle(posDiff), m_crew.submarine.transform.wrotation).fabs;
				if (dgr2rad(90.0) < noseAngleToTgt)
				{
					needToTurnNose = true;
					needToSwimFast = true;
				}
			}
			// speed up our approach
			if (currentRange > firingRange * 0.85)
			{
				if (currentRange > firingRange)
					needToBoost = true;
				needToTurnNose = true;
				needToSwimFast = true;
			}
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.destination;
			if (needToTurnNose)
			{
				whereToSwim.destination = curTgtPos;
			}
			else
			{
				// we simply maintain our current course
				whereToSwim.destination = m_crew.submarine.transform.wposition +
					1000.0 * m_crew.submarine.transform.wforward;
			}
			NavigationSpeed speed = needToSwimFast ?
				NavigationSpeed.tactical : NavigationSpeed.silent;
			if (needToBoost)
				speed = NavigationSpeed.fast;
			giveOrdersToHelmsman(whereToSwim, speed, HelmsmanOrderGoal.attack);
			return ExecutionResult.success;
		}
	}


	private final class RequestPing: FixedCostActionNode
	{
		this(float power = 1.0f, string file = __FILE__, size_t line = __LINE__)
		{
			super("Emit one sonar ping", 1000, false, file, line);
			m_power = power;
			final switch (m_difficulty)
			{
				case (BOT_DIFFICULTY.easy):
					m_detectionMargin = 8.0f;
					break;
				case (BOT_DIFFICULTY.medium):
					m_detectionMargin = 5.0f;
					break;
				case (BOT_DIFFICULTY.hard):
					m_detectionMargin = 3.0f;
					break;
			}
		}

		private float m_detectionMargin = 0.0f;
		private float m_power = 1.0f;

		enum float CLASSIFICATION_MARGIN = 50.0f;

		override @property bool shouldBeRunning()
		{
			return hasActiveSonar(m_crew.submarine);
		}

		override ExecutionResult onTicksConsumed()
		{
			m_lastPing = simulator.worldTime;
			ActiveSonar sonar = m_crew.submarine.sonar;
			float maxIlevel = sonar.proto.maxPeakIlevel;
			float minIlevel = sonar.proto.minPeakIlevel;
			SonarPing ping = sonar.startPing(minIlevel + m_power * (maxIlevel - minIlevel));
			simulator.acous.registerSource(ping);
			ReflectorImprint[] imprints = sonar.estimateReflectors(
				simulator.acous.reflectors.filter!(
					r => AcousticEnv.filterBySonarFilter(sonar, r)));
			// ping returned imprints
			trace("AI ping resulted in imprints: ", imprints);
			// we go through all imprints and provide position data to CIC (crew state)
			foreach (ReflectorImprint ri; imprints)
			{
				Vessel v = cast(Vessel) ri.reflector.owner;
				if (v is null)
					continue;
				if (ri.signalLevel - ri.noiseLevel < m_detectionMargin)
					continue;
				if (v !in m_crew.state.contacts)
				{
					Contact* newCtc = new Contact(v);
					trace("Adding new contact for reflector imprint ", ri,
						", vessel ", v);
					m_crew.state.contacts[v] = newCtc;
				}
				Contact* ctc = m_crew.state.contacts[v];
				ctc.lastActiveSonarData = simulator.worldTime;
				ctc.activeSonarPoints += ri.signalLevel - ri.noiseLevel;
				if (ctc.classification == ContactClass.unknown &&
					ctc.activeSonarPoints > CLASSIFICATION_MARGIN)
				{
					AIAcoustic.classifyAndRelate(ctc, v, m_crew.side);
				}
			}
			return ExecutionResult.success;
		}
	}

	private final class FireOneDecoy: FixedCostActionNode
	{
		this(string description = "Choose open decoy tube and fire it",
			int cost = 500,
			string file = __FILE__, size_t line = __LINE__)
		{
			super(description, cost, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
				t.state == TubeState.open &&
				t.type == TubeType.decoy &&
				t.loadedWeapon.startsWith("Decoy"));
		}

		override ExecutionResult onTicksConsumed()
		{
			auto tubes = m_crew.submarine.tubeRange;
			Tube chosenTube;
			string weapon;
			foreach (Tube tube; tubes)
			{
				if (tube.state == TubeState.open &&
					tube.type == TubeType.decoy &&
					tube.loadedWeapon.startsWith("Decoy"))
				{
					// we have found the tube that can be launched
					chosenTube = tube;
					weapon = tube.loadedWeapon;
					break;
				}
			}
			if (chosenTube is null)
				return ExecutionResult.failure;
			trace("AI launching ", weapon);
			TubeOperationResult res = chosenTube.processLaunchRequest(weapon, null);
			assert(res.tubeChanged);
			m_lastDecoyFire = simulator.worldTime;
			return ExecutionResult.success;
		}
	}

	private class FireOneTorpedo: FixedCostActionNode
	{
		this(string description = "Open the tube and fire onto the main target",
			int cost = 1000, string file = __FILE__, size_t line = __LINE__)
		{
			super(description, cost, false, file, line);
		}

		protected vec2d getTargetPos()
		{
			return mainContact().solution.extrapolatedPos(simulator.worldTime);
		}

		protected vec2d getTargetVel()
		{
			return mainContact().solution.velocity;
		}

		override ExecutionResult onTicksConsumed()
		{
			auto tubes = m_crew.submarine.tubeRange;
			if (!torpedoBudgetOk)
				return ExecutionResult.running;
			Tube chosenTube;
			foreach (Tube tube; tubes)
			{
				if (tube.state != TubeState.unloading &&
					tube.state != TubeState.loading &&
					tube.type == TubeType.standard &&
					tube.loadedWeapon != null)
				{
					// we have found the tube that can be opened
					chosenTube = tube;
					if (tube.state != TubeState.open)
					{
						tube.processStateRequest(TubeState.open);
						return ExecutionResult.running;
					}
					break;
				}
			}
			if (chosenTube is null)
				return ExecutionResult.running;
			WeaponParamValue[] wpValues = getFiringParameters(
				getTargetPos(), getTargetVel(),
				chosenTube, chosenTube.loadedWeapon);
			if (wpValues is null)
			{
				trace("cannot launch, maybe too far");
				return ExecutionResult.failure;
			}
			trace("AI launching ", chosenTube.loadedWeapon,
				" torp with parameters ", wpValues);
			TubeOperationResult res = chosenTube.processLaunchRequest(
				chosenTube.loadedWeapon, wpValues);
			assert(res.tubeChanged);
			m_lastFire = simulator.worldTime;
			m_torpedoBudget -= 100.0f;
			return ExecutionResult.success;
		}

		// https://wiki.unity3d.com/index.php/Calculating_Lead_For_Projectiles
		static float interceptTime(float shotSpeed, vec2d tgtRelPos, vec2d tgtVel)
		{
			float velocitySquared = tgtVel.squaredLength;
			if (velocitySquared < 0.001f)
				return 0f;
			float a = velocitySquared - shotSpeed * shotSpeed;
			// handle similar velocities
			if (fabs(a) < 0.001f)
			{
				float t = -tgtRelPos.squaredLength /
						2.0f * dot(tgtRelPos, tgtVel);
				return max(t, 0.0f); //don't shoot back in time
			}
			float b = 2.0f * dot(tgtVel, tgtRelPos);
			float c = tgtRelPos.squaredLength;
			float determinant = b * b - 4f * a * c;

			if (determinant > 0.0f)
			{ //determinant > 0; two intercept paths (most common)
				float t1 = (-b + sqrt(determinant))/(2f*a);
				float t2 = (-b - sqrt(determinant))/(2f*a);
				if (t1 > 0f)
				{
					if (t2 > 0f)
						return min(t1, t2); //both are positive
					else
						return t1; //only t1 is positive
				}
				else
					return max(t2, 0f); //don't shoot back in time
			}
			else if (determinant < 0f) //determinant < 0; no intercept path
				return 0f;
			else //determinant = 0; one intercept path, pretty much never happens
				return max(-b/(2f*a), 0f); //don't shoot back in time
		}

		/// Tries to find shooting solution that achieves minimal distance between
		/// target and torpedo. Torpedo speed is assumed to be fixed beforehand.
		void iterativeShootingRoutine(vec2d tgtPos, vec2d tgtVel,
			vec2d torpStartPos, double torpSpd, double maxTorpDist,
			out float initialCourseEst,
			out double course, out float runDist, out float minFoundDist,
			int iterCount = 10)
		{
			// There is an analythical solution to this, but we won't use it to keep
			// the code unchanged in case we will wish to loosen the assumptions about
			// torp trajectory

			float distanceSeeker(float course)
			{
				vec2d tgt = tgtPos;
				vec2d torp = torpStartPos;
				vec2d torpVel = courseVector(course) * torpSpd;
				float minDist = float.max;
				float prevDist = float.max;
				double distPassed = 0.0;
				while (distPassed < maxTorpDist)
				{
					torp += torpVel;
					tgt += tgtVel;
					float dist = (torp - tgt).length;
					if (dist < minDist)
					{
						minDist = dist;
					}
					else if (dist >= prevDist)
					{
						// we've found minimum. Thanks to binarySearch's structure
						// the last call to this will be almost optimal
						runDist = distPassed;
						break;
					}
					prevDist = dist;
					distPassed += torpSpd;
				}
				runDist = distPassed;
				return minDist;
			}

			vec2d tgtRelPos = tgtPos - torpStartPos;
			vec2d leftHandVec = rotateVector(tgtRelPos, PI_2);
			float angleSign = sgn(dot(leftHandVec, tgtVel));
			if (angleSign == 0.0f)
				angleSign = 1.0f;
			// estimate intercept point
			float secsToNaiveIntercept = interceptTime(torpSpd, tgtRelPos, tgtVel);
			vec2d naiveIntercept = tgtPos + secsToNaiveIntercept * tgtVel;
			initialCourseEst = courseAngle(naiveIntercept - torpStartPos);
			// trace("initialCourseEst: ", initialCourseEst);
			float bestDistance;
			float betterCourse = binarySearch(&distanceSeeker, bestDistance,
				initialCourseEst, angleSign * dgr2rad(15), iterCount);
			course = betterCourse;
			minFoundDist = bestDistance;
			// trace(m_crew.submarine, " iterativeShootingRoutine course:", rad2dgr(course),
			// 	" runDist: ", runDist, " minDist: ", minFoundDist);
		}

		protected WeaponParamValue[] getFiringParameters(
			vec2d tgtPos, vec2d tgtVel, Tube tube, string weapon)
		{
			// FIXME
			WeaponParamValue sensorMode = WeaponParamValue(WeaponParamType.sensorMode);
			WeaponSensorMode chosenSensorMode = WeaponSensorMode.active;
			sensorMode.sensorMode = chosenSensorMode;
			if (m_difficulty != BOT_DIFFICULTY.easy)
			{
				if (uniform!"[]"(0, 2) == 0)
				{
					// 1 of 3 torps is passive
					chosenSensorMode = WeaponSensorMode.passive;
					sensorMode.sensorMode = chosenSensorMode;
				}
			}

			WeaponSearchPattern pattern = WeaponSearchPattern.snake;
			if (m_difficulty != BOT_DIFFICULTY.easy)
			{
				if (uniform!"[]"(0, 4) == 0)
				{
					// 1 of 4 torps is spiral
					pattern = WeaponSearchPattern.spiral;
				}
			}
			WeaponParamValue searchParam = WeaponParamValue(WeaponParamType.searchPattern);
			searchParam.searchPattern = pattern;

			WeaponFactory factory = Globals.entityDb.getWeaponFactory(weapon);

			// choose active speed
			WeaponParamValue marchSpeed = WeaponParamValue(WeaponParamType.marchSpeed);
			marchSpeed.speed = uniform!"[]"(factory.marchSpeedRange.min,
				factory.marchSpeedRange.max);
			WeaponParamValue activeSpeed = WeaponParamValue(WeaponParamType.activeSpeed);
			activeSpeed.speed = marchSpeed.speed;
			if (chosenSensorMode == WeaponSensorMode.passive)
			{
				// passive sensors are not good on max speed
				activeSpeed.speed = min(
					activeSpeed.speed, factory.activeSpeedRange.max - 2.0f);
			}

			float noLeadCourse;
			double course;
			float runDist;
			float minAchievedDist;
			// trace("before iterativeShootingRoutine: ", tgtPos, " ", tgtVel);
			iterativeShootingRoutine(tgtPos, tgtVel, tube.transform.wposition,
				marchSpeed.speed, factory.activationRange.max, noLeadCourse, course,
				runDist, minAchievedDist, 15);

			if (minAchievedDist > 500.0)
			{
				trace("failed to calculate torp launch course, minAchievedDist is ",
					minAchievedDist, " runDist: ", runDist);
				return null;
			}

			if (runDist < 2000)
			{
				// trace("Cannot use spiral so close to own sub");
				pattern = WeaponSearchPattern.snake;
				searchParam.searchPattern = pattern;
			}

			WeaponParamValue courseParam = WeaponParamValue(WeaponParamType.marchCourse);
			courseParam.course = course;

			// easy bot always shoots with perfect lead
			if (m_difficulty != BOT_DIFFICULTY.easy)
			{
				// it is dumb to always lead perfectly. One must randomize angle lead
				float[2] courses;
				float bumpedNoLeadCourse = noLeadCourse + (course - noLeadCourse) * 0.25f;
				courses[] = [bumpedNoLeadCourse, course];
				sort(courses[]);
				// trace("cources: ", courses);
				if (courses[1] > courses[0])
					courseParam.course = uniform(courses[0], courses[1]);
				else
					courseParam.course = courses[0];
			}

			WeaponParamValue activationRangeParam = WeaponParamValue(
				WeaponParamType.activationRange);
			if (pattern == WeaponSearchPattern.spiral)
				activationRangeParam.range = runDist;
			else
			{
				activationRangeParam.range = clamp(
					runDist - (1000.0 + runDist / 10),
					factory.activationRange.min, factory.activationRange.max);
			}

			WeaponParamValue[] res = [courseParam, activationRangeParam, searchParam,
				marchSpeed, activeSpeed, sensorMode];
			return res;
		}
	}

	private final class FireOneTorpedoOnDanger: FireOneTorpedo
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Open the tube and fire onto the main danger", 1000,
				file, line);
		}

		protected override vec2d getTargetPos()
		{
			// fire at the point of danger's origin
			return mainDanger().solution.extrapolatedPos(simulator.worldTime -
				(mainDanger.age + 20.0f).to!usecs_t * 1_000_000L);
		}

		protected override vec2d getTargetVel()
		{
			return mainDanger().solution.velocity;
		}

		protected override WeaponParamValue[] getFiringParameters(
			vec2d tgtPos, vec2d tgtVel, Tube tube, string weapon)
		{
			assert(weapon == "Minoga");
			vec2d posDiff = tgtPos - tube.transform.wposition;
			// first we check that the torp is not running away from us
			if (dot(posDiff, tgtVel) >= 0.0)
			{
				trace("main danger is not approaching us, won't shoot there");
				return null;
			}
			WeaponFactory factory = Globals.entityDb.getWeaponFactory(weapon);
			WeaponParamValue courseParam = WeaponParamValue(WeaponParamType.marchCourse);
			courseParam.course = courseAngle(posDiff);
			WeaponParamValue activationRangeParam = WeaponParamValue(
				WeaponParamType.activationRange);
			activationRangeParam.range = clamp(activationRangeGain * posDiff.length,
				factory.activationRange.min, factory.activationRange.max);
			WeaponParamValue search = WeaponParamValue(WeaponParamType.searchPattern);
			search.searchPattern = WeaponSearchPattern.snake;
			WeaponParamValue speed = WeaponParamValue(WeaponParamType.activeSpeed);
			speed.speed = uniform!"[]"(factory.activeSpeedRange.min,
				factory.activeSpeedRange.max);
			WeaponParamValue[] res = [courseParam, activationRangeParam, search, speed];
			if (m_difficulty != BOT_DIFFICULTY.easy)
			{
				// pasive torpedo is too dangerous, give it to medium or hard bots
				if (uniform!"[]"(0, 2) == 0)
				{
					// 1 of 3 torps is passive
					WeaponParamValue sensorMode = WeaponParamValue(
						WeaponParamType.sensorMode);
					sensorMode.sensorMode = WeaponSensorMode.passive;
					res ~= sensorMode;
				}
			}
			return res;
		}

		protected @property float activationRangeGain()
		{
			return 1.0f;
		}
	}

	private BehaviourTreeNode easyCombatTree()
	{
		BehaviourTreeNode node = new FallbackNode(
			"Easy captain always defends itself first, then attacks",
			[
			new SequenceNode("Find dangers and dodge them",
			[
				new ChooseMostDangerousTorp(),
				new EvadeMainDangerIfNeededTangent(NavigationSpeed.fast)
			], true),	// memory true to sequence over them
			new SequenceNode("Simply attack if possible", [
				new ConditionNode("if we have ammo",
					() => m_crew.submarine.haveTorpedoes),
				new FallbackNode("use or find main target", [
					new ConditionNode("do we have main target?",
						() => m_mainTarget !is null),
					new ChooseClosestEnemyContact(),
					new SequenceNode("Rare ping when in search mode", [
						new ConditionNode("Ping not more than once in 5 minutes
							and after 3 minutes alive", () =>
							(simulator.worldTime - m_crew.submarine.registerTime > 180_000_000L) &&
							(simulator.worldTime - m_lastPing > 300_000_000L)),
						new RequestPing(0.4f)
					])
				]),
				new FallbackNode("when we have main target", [
					new DropStaleMainTarget(),
					new ParallelNode("Parallel navigation and fire control", [
						new SwimCloserToMainTarget(),
						new SequenceNode("Shoot while in range", [
							new EnsureTorpedoesLoading(true),
							new ConditionNode("Close enough", () =>
								rangeFromContact(mainContact) <=
									effectiveFiringRange(
										m_crew.submarine, mainContact.solution)),
							new ConditionNode("Haven't fired in the last 90 seconds", () =>
								simulator.worldTime - m_lastFire > 90_000_000L),
							new ConditionNode("Burst protection", () => torpedoBudgetOk()),
							new FireOneTorpedo()
						]),
					], 0)
				])
			])
		]);
		return node;
	}

	private BehaviourTreeNode mediumCombatTree()
	{
		BehaviourTreeNode node = new RoundRobinNode(
			"Medium captain decouples navigation from firing",
			[
				new ChooseMostDangerousTorp(),
				new EnsureTorpedoesLoading(false),
				new EnsureDecoysLoading(),
				new EnsureDecoyTubesOpening(),
				new FallbackNode("use or find main target", [
					new ConditionNode("do we have main target?",
						() => m_mainTarget !is null),
					new ChooseClosestEnemyContact()
				]),
				new SequenceNode("Fire decoys when there is danger", [
					new ConditionNode("There is main danger", () =>
						m_mainDanger !is null),
					new ConditionNode("Haven't fired in the last 60 seconds", () =>
						simulator.worldTime - m_lastDecoyFire > 60_000_000L),
					new FireOneDecoy()
				]),
				new SequenceNode("Fire torpedo snapshot towards the main danger", [
					new ConditionNode("There is an enemy main danger", () =>
						m_mainDanger !is null && mainDanger.relation == ContactRelation.enemy),
					new ConditionNode("Haven't fired in the last 90 seconds", () =>
						simulator.worldTime - m_lastFire > 90_000_000L),
					new FireOneTorpedoOnDanger()
				]),
				new SequenceNode("Rare ping when in search mode", [
					new ConditionNode("There is no danger", () =>
						m_mainDanger is null && m_mainTarget is null),
					new ConditionNode("Ping not more than once in 5 minutes
						and after 2 minutes alive", () =>
						(simulator.worldTime - m_crew.submarine.registerTime > 120_000_000L) &&
						(simulator.worldTime - m_lastPing > 300_000_000L)),
					new RequestPing(0.85f)
				]),
				new SequenceNode("Active ping when in danger", [
					new ConditionNode("There is danger", () =>
						m_mainDanger !is null),
					new ConditionNode("Ping not more than once in 1 minutes", () =>
						simulator.worldTime - m_lastPing > 60_000_000L),
					new RequestPing()
				]),
				new ParallelNode("Parallel navigation and fire control", [
					new FallbackNode("we either move offensively or defensively", [
						new EvadeMainDangerIfNeededTangent(NavigationSpeed.flank),
						new KeepDistanceFromMainTarget()
					]),
					new DropStaleMainTarget(),
					new SequenceNode("Attack sequence", [
						new ConditionNode("if we have ammo",
							() => m_crew.submarine.haveTorpedoes),
						new ConditionNode("We have main target",
							() => m_mainTarget !is null),
						new ConditionNode("Close enough", () =>
							rangeFromContact(mainContact) <=
								effectiveFiringRange(
									m_crew.submarine, mainContact.solution)),
						new ConditionNode("Haven't fired in the last 60 seconds",
							() => simulator.worldTime - m_lastFire > 60_000_000L),
						new ConditionNode("Burst protection", () => torpedoBudgetOk()),
						new FireOneTorpedo()
					])
				])
		], 200);
		return node;
	}

	private static BehaviourTreeNode[] removeNulls(BehaviourTreeNode[] nodes)
	{
		return nodes.filter!(a => a !is null).array;
	}

	private BehaviourTreeNode buildEasyCaptainBt()
	{
		bool combatShip = isCombatCapable(m_crew.submarine);
		BehaviourTreeNode[] rootParallelNodes = [
			new FallbackNode("static priorities", removeNulls([
				new ProcessNewOrder(),
				combatShip ? easyCombatTree() : null,
				orderExecutionTree()
			])),
			combatShip ? new UpdateSolutions() : null
		];
		BehaviourTreeNode res = new ParallelNode("Easy captain AI",
			removeNulls(rootParallelNodes));
		return res;
	}

	private BehaviourTreeNode buildMediumCaptainBt()
	{
		bool combatShip = isCombatCapable(m_crew.submarine);
		BehaviourTreeNode[] rootParallelNodes = [
			new FallbackNode("static priorities", removeNulls([
				new ProcessNewOrder(),
				combatShip ? mediumCombatTree() : null,
				orderExecutionTree()
			])),
			combatShip ? new UpdateSolutions() : null
		];
		BehaviourTreeNode res = new ParallelNode("Medium captain AI",
			removeNulls(rootParallelNodes));
		return res;
	}
}