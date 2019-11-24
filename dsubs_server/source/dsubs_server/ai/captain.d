module dsubs_server.ai.captain;

import std.algorithm: any, filter, map, sort;
import std.array: array;

import dsubs_common.containers.circqueue;
import dsubs_common.math.angles;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.weaponry;
import dsubs_server.torpedo;
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

	@property vec2d currentPos() const
	{
		return extrapolatedPos(Globals.sim.worldTime);
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
		return (Globals.sim.worldTime - createdAt) / 1000_000L;
	}

	/// Solution age in seconds
	@property float solutionAge() const
	{
		assert(solution.set);
		return (Globals.sim.worldTime - solution.atTime) / 1000_000L;
	}

	// 1.0f + is to prevent division by zero

	@property float hydrophoneDataAge() const
	{
		return 1.0f + (Globals.sim.worldTime - m_lastHydrophoneData) / 1000_000L;
	}

	@property float activeSonarDataAge() const
	{
		return 1.0f + (Globals.sim.worldTime - m_lastActiveSonarData) / 1000_000L;
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

double effectiveFiringRange(const Submarine sub)
{
	// FIXME
	return 6000.0;
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

	private
	{
		AICrew m_crew;
		BehavourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;

		CrewGoal m_activeGoal;
		HelmsmanOrderGoal m_helmsmansOrderGoal;
		usecs_t m_lastOrderToHelmsman;
	}

	private @property bool helmsmanOrderOnCooldown()
	{
		return (Globals.sim.worldTime - m_lastOrderToHelmsman) < 15_000_000L;
	}

	private void giveOrdersToHelmsman(WhereToSwim whereToSwim, NavigationSpeed navSpeed,
		HelmsmanOrderGoal goal)
	{
		m_crew.m_helmsman.whereToSwimOrder.pushBack(whereToSwim);
		m_crew.m_helmsman.navigationSpeedOrder.pushBack(navSpeed);
		m_helmsmansOrderGoal = goal;
		m_lastOrderToHelmsman = Globals.sim.worldTime;
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

	void execute()
	{
		int ticks = m_ticksPerExecute;
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
			trace("Ordering helmsman to swim to destination");
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

	private BehavourTreeNode orderExecutionTree()
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
		Vessel m_mainDanger;
		usecs_t m_lastFire;
		usecs_t m_lastDecoyFire;
	}

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
		return (ctc.solution.currentPos - m_crew.submarine.transform.wposition).length;
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
				if (Globals.sim.worldTime - ctc.solution.atTime < SOLUTION_CONST_PERIOD)
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
					uniform(0.0f, maxPosError) * courseVector(uniform(0, 2 * PI));
				ctc.solution.velocity = trueVel +
					uniform(0.0f, maxVelError) * courseVector(uniform(0, 2 * PI));
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
					c.vessel, (c.solution.currentPos - curPos).length)).array;
			if (enemyVessels.length == 0)
				return ExecutionResult.failure;
			enemyVessels.sort!((a, b) => a.range < b.range);
			m_mainTarget = enemyVessels[0].v;
			trace("Choosing closest target ", m_mainTarget, " as main");
			return ExecutionResult.success;
		}
	}

	private final class EvadeMainDangerIfNeeded: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("If there is main danger, evade it", 600, false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			invertShouldBeRunning = m_mainDanger !is null;
			return invertShouldBeRunning &&
				(!helmsmanOrderOnCooldown ||
					m_helmsmansOrderGoal != HelmsmanOrderGoal.defense);
		}

		private vec2d getEvasionDirection()
		{
			Solution torpSol = mainDanger.solution;
			vec2d relPos = torpSol.currentPos - m_crew.submarine.transform.wposition;
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
			giveOrdersToHelmsman(wts, NavigationSpeed.flank, HelmsmanOrderGoal.defense);
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
					c.relation == ContactRelation.enemy &&
					c.classification == ContactClass.weapon &&
					c.solution.positionKnown &&
					c.solutionAge < MAX_SOLUTION_AGE);
		}

		enum double MIN_MISS_WORRY = 1200.0;
		enum float MAX_SOLUTION_AGE = 120.0f;

		private double getDanger(Solution torpSol)
		{
			assert(torpSol.set);
			assert(torpSol.positionKnown);
			vec2d relVel = torpSol.velocity - m_crew.submarine.rigidBody.kinet.vel;
			vec2d relPos = torpSol.currentPos - m_crew.submarine.transform.wposition;
			// if torp swims perfectly on us, relVel is parallel to -relPos.
			if (dot(relVel.normalized, relPos.normalized) >= 0.0)
				return 0.0;
			double angle = angleBetween(relVel, relPos);
			double totalMiss = relPos.length * sin(angle).fabs;
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
					c.relation == ContactRelation.enemy &&
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
				m_mainDanger = null;
				return ExecutionResult.failure;
			}
			if (m_mainDanger != dangers[$-1].v)
			{
				m_mainDanger = dangers[$-1].v;
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
				m_crew.state.contacts.remove(m_mainTarget);
				m_mainTarget = null;
				return ExecutionResult.success;
			}
			return ExecutionResult.failure;
		}
	}

	private final class EnsureTorpedoesLoading: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Initiate torpedoes loading into free tubes", 400, true, file, line);
		}

		override @property bool shouldBeRunning()
		{
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
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
					assert(res.tubeChanged);
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
			if (room.getWeaponCount("Decoy(active)") == 0)
				return false;
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
				t.state == TubeState.dry &&
				t.type == TubeType.decoy &&
				t.loadedWeapon == null);
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
					TubeOperationResult res = tube.processLoadRequest("Decoy(active)");
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
				t.loadedWeapon == "Decoy(active)");
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
			if (helmsmanOrderOnCooldown && m_helmsmansOrderGoal != HelmsmanOrderGoal.attack)
				return ExecutionResult.success;
			double firingRange = effectiveFiringRange(m_crew.submarine);
			vec2d posDiff = mainContact.solution.currentPos -
				m_crew.submarine.transform.wposition;
			double currentRange = posDiff.length;
			bool needToSwimFast;
			// speed up to turn our nose
			if (dgr2rad(60.0) < angleDist(
				courseAngle(posDiff), m_crew.submarine.transform.wrotation).fabs)
				needToSwimFast = true;
			// speed up to approach
			if (currentRange > firingRange)
				needToSwimFast = true;
			// trace("Giving order to approach main target's solution");
			WhereToSwim whereToSwim;
			whereToSwim.type = WhereToSwimType.destination;
			whereToSwim.destination = mainContact.solution.currentPos;
			NavigationSpeed speed = needToSwimFast ?
				NavigationSpeed.tactical : NavigationSpeed.silent;
			giveOrdersToHelmsman(whereToSwim, speed, HelmsmanOrderGoal.attack);
			// 	trace("helmsman message queue on cooldown");
			return ExecutionResult.success;
		}
	}

	private final class FireOneDecoy: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Choose open decoy tube and fire it", 500,
				false, file, line);
		}

		override @property bool shouldBeRunning()
		{
			auto tubes = m_crew.submarine.tubeRange;
			return tubes.any!(t =>
				t.state == TubeState.open &&
				t.type == TubeType.decoy &&
				t.loadedWeapon == "Decoy(active)");
		}

		override ExecutionResult onTicksConsumed()
		{
			auto tubes = m_crew.submarine.tubeRange;
			Tube chosenTube;
			foreach (Tube tube; tubes)
			{
				if (tube.state == TubeState.open &&
					tube.type == TubeType.decoy &&
					tube.loadedWeapon == "Decoy(active)")
				{
					// we have found the tube that can be launched
					chosenTube = tube;
					break;
				}
			}
			if (chosenTube is null)
				return ExecutionResult.failure;
			trace("AI launching active decoy");
			TubeOperationResult res = chosenTube.processLaunchRequest("Decoy(active)", null);
			assert(res.tubeChanged);
			m_lastDecoyFire = Globals.sim.worldTime;
			return ExecutionResult.success;
		}
	}

	private final class FireOneTorpedo: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Open the tube and fire onto the main target", 1000,
				false, file, line);
		}

		override ExecutionResult onTicksConsumed()
		{
			auto tubes = m_crew.submarine.tubeRange;
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
			WeaponParamValue[] wpValues = getFiringParameters(chosenTube, "Minoga");
			trace("AI launching Minoga torp with parameters ", wpValues);
			TubeOperationResult res = chosenTube.processLaunchRequest("Minoga", wpValues);
			assert(res.tubeChanged);
			m_lastFire = Globals.sim.worldTime;
			return ExecutionResult.success;
		}

		private WeaponParamValue[] getFiringParameters(Tube tube, string weapon)
		{
			assert(weapon == "Minoga");
			vec2d posDiff = mainContact.solution.currentPos -
				tube.transform.wposition;
			WeaponFactory factory = Globals.entityDb.getWeaponFactory(weapon);
			WeaponParamValue courseParam = WeaponParamValue(WeaponParamType.marchCourse);
			courseParam.course = courseAngle(posDiff);
			WeaponParamValue activationRangeParam = WeaponParamValue(
				WeaponParamType.activationRange);
			activationRangeParam.range = clamp(0.5 * posDiff.length,
				factory.activationRange.min, factory.activationRange.max);
			WeaponParamValue search = WeaponParamValue(WeaponParamType.searchPattern);
			search.searchPattern = WeaponSearchPattern.snake;
			return [courseParam, activationRangeParam, search];
		}
	}

	private BehavourTreeNode easyCombatTree()
	{
		BehavourTreeNode node = new SequenceNode("Simply attack if if possible", [
			new ConditionNode("if we have ammo",
				() => m_crew.submarine.haveTorpedoes),
			new FallbackNode("use or find main target", [
				new ConditionNode("do we have main target?",
					() => m_mainTarget !is null),
				new ChooseClosestEnemyContact()
			]),
			new FallbackNode("when we have main target", [
				new DropStaleMainTarget(),
				new ParallelNode("Parallel navigation and fire control", [
					new SwimCloserToMainTarget(),
					new SequenceNode("Shoot while in range", [
						new EnsureTorpedoesLoading(),
						new ConditionNode("Close enough", () =>
							rangeFromContact(mainContact) <=
								effectiveFiringRange(m_crew.submarine)),
						new ConditionNode("Haven't fired in the last 90 seconds", () =>
							Globals.sim.worldTime - m_lastFire > 90_000_000L),
						new FireOneTorpedo()
					]),
				], 0)
			])
		]);
		return node;
	}

	private BehavourTreeNode mediumCombatTree()
	{
		BehavourTreeNode node = new RoundRobinNode(
			"Medium captain decouples navigation from firing",
			[
				new ChooseMostDangerousTorp(),
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
					new ConditionNode("Haven't fired in the last 90 seconds", () =>
						Globals.sim.worldTime - m_lastDecoyFire > 90_000_000L),
					new FireOneDecoy()
				]),
				new SequenceNode("General attack sequence", [
					new FallbackNode("we either move offensively or defensively", [
						new EvadeMainDangerIfNeeded(),
						new SwimCloserToMainTarget()
					]),
					new ConditionNode("if we have ammo",
						() => m_crew.submarine.haveTorpedoes),
					new FallbackNode("when we have main target", [
						new DropStaleMainTarget(),
						new EnsureTorpedoesLoading(),
						new ConditionNode("Close enough", () =>
							rangeFromContact(mainContact) <=
								effectiveFiringRange(m_crew.submarine)),
						new ConditionNode("Haven't fired in the last 90 seconds", () =>
							Globals.sim.worldTime - m_lastFire > 90_000_000L),
						new FireOneTorpedo()
					])
				])
		], 200);
		BehavourTreeNode wrapper = new SequenceNode(
			"return Seccess only when no main target", [
				node,
				new ConditionNode(null, () => m_mainTarget is null && m_mainDanger is null)
			]);
		return wrapper;
	}

	private static BehavourTreeNode[] removeNulls(BehavourTreeNode[] nodes)
	{
		return nodes.filter!(a => a !is null).array;
	}

	private BehavourTreeNode buildEasyCaptainBt()
	{
		bool combatShip = isCombatCapable(m_crew.submarine);
		BehavourTreeNode[] rootParallelNodes = [
			new FallbackNode("static priorities", removeNulls([
				new ProcessNewOrder(),
				combatShip ? easyCombatTree() : null,
				orderExecutionTree()
			])),
			combatShip ? new UpdateSolutions() : null
		];
		BehavourTreeNode res = new ParallelNode("Easy captain AI",
			removeNulls(rootParallelNodes));
		return res;
	}

	private BehavourTreeNode buildMediumCaptainBt()
	{
		bool combatShip = isCombatCapable(m_crew.submarine);
		BehavourTreeNode[] rootParallelNodes = [
			new FallbackNode("static priorities", removeNulls([
				new ProcessNewOrder(),
				combatShip ? mediumCombatTree() : null,
				orderExecutionTree()
			])),
			combatShip ? new UpdateSolutions() : null
		];
		BehavourTreeNode res = new ParallelNode("Medium captain AI",
			removeNulls(rootParallelNodes));
		return res;
	}
}