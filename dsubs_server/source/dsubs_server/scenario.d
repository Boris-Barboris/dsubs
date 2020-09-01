module dsubs_server.scenario;

import std.algorithm;
import std.array: array;
import std.random: uniform, uniform01;
import std.range: walkLength;
import std.container.rbtree;
import std.uuid;

import dsubs_common.math.angles;
import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.containers.array;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.animal;
import dsubs_server.weaponry;
import dsubs_server.submarine: Submarine;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.player;
import dsubs_server.bots;
import dsubs_server.simulator;
import dsubs_server.ai.captain;
import dsubs_server.ai.common;
import dsubs_server.scenarios.battleroyale;


/// Action to run after specified clock time.
struct AlarmClockAction
{
	usecs_t when;
	void delegate() action;
}

private alias AlarmClockActionCollection =
	RedBlackTree!(AlarmClockAction, "a.when < b.when", true);


struct AlarmCollection
{
	private
	{
		AlarmClockActionCollection m_events;
	}

	void initialize()
	{
		m_events = new AlarmClockActionCollection();
	}

	void put(AlarmClockAction event)
	{
		m_events.insert(event);
	}

	void triggerAlarms(usecs_t clockTime)
	{
		auto toRun = m_events.lowerBound(AlarmClockAction(clockTime));
		foreach (AlarmClockAction evt; toRun)
			evt.action();
		// Evicts the alarms
		m_events.remove(toRun);
	}
}


enum ShouldSimTerminate
{
	no,
	yes
}


/// Running instance of scenario with all necessary internal state.
abstract class Scenario
{
	protected Simulator m_simulator;
	protected ScenarioSpawner m_spawner;

	final @property Simulator simulator() { return m_simulator; }
	final @property ScenarioSpawner spawner() { return m_spawner; }

	/// Scenario can only be instantiated for a simulator. Binding is eager.
	this(Simulator sim)
	{
		assert(sim);
		m_simulator = sim;
		m_simulator.scenario = this;
	}

	abstract void onBeforeSimulation();

	/// scenario is responsible for sending SimFlowEndRes messages to players.
	abstract ShouldSimTerminate onAfterSimulation();

	/// Scenario is responsible for picking true world-space player spawn position.
	abstract void selectPlayerSpawnPosition(Player player,
		out vec2d position, out double rotation);

	/// Scenario is responsible for generating initial overlay state and briefing
	/// for (re)connecting player.
	abstract void generateBriefing(Player player, out MapElement[] mapOverlayEls,
		out ChatMessage briefing);
}


struct Campaign
{
	string name;
	string description;
	CampaignScenarioSpawner[] scenarios;
}


/// Scenario can be a persistent-sim, standalone or part of a campaign.
/// Various checks must be performed by the server to ensure spawn request validity.
abstract class ScenarioSpawner
{
	private
	{
		const AvailableScenarioConstants m_constants;
		Scenario delegate(Simulator sim) m_factory;
	}

	// publicly-visible information.
	@property ref const(AvailableScenarioConstants) constants() const
	{
		return m_constants;
	}

	this(const AvailableScenarioConstants constants, Scenario delegate(Simulator sim) factory)
	{
		m_constants = constants;
		m_factory = factory;
	}

	/// Throws if some modules/subs are not allowed by the scenario.
	void validateSpawnRequest(Player player, const SpawnReq req)
	{
		const EntityDbShort allowedTitles = m_constants.allowedEntities;
		enforce(canFind(allowedTitles.controllableSubNames, req.submarineName),
			"invalid submarineName " ~ req.submarineName);
		enforce(canFind(allowedTitles.propulsorNames, req.propulsorName),
			"invalid propulsorName " ~ req.propulsorName);
		foreach (const TubeSpawnState ltl; req.loadableTubeLoadouts)
			if (ltl.loadedWeapon)
				enforce(canFind(allowedTitles.weaponNames, ltl.loadedWeapon),
					"invalid loadedWeapon " ~ ltl.loadedWeapon);
		foreach (const AmmoRoomFullState arl; req.ammoRoomLoadouts)
		{
			foreach (const WeaponCount wc; arl.storedWeapons)
				enforce(canFind(allowedTitles.weaponNames, wc.weaponName),
					"invalid weaponName " ~ wc.weaponName);
		}
	}

	@property ScenarioType scenarioType() const;

	Scenario createSimulatorAndScenario(string simId = null)
	{
		if (simId == null)
			simId = randomUUID().toString();
		Simulator sim = new Simulator(simId);
		Scenario res = m_factory(sim);
		res.m_spawner = this;
		return res;
	}
}


private final class StandaloneScenarioSpawner: ScenarioSpawner
{
	this(AvailableScenarioConstants constants, Scenario delegate(Simulator sim) factory)
	{
		super(constants, factory);
	}

	override @property ScenarioType scenarioType() const
	{
		return ScenarioType.standalone;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator);
		assert(req.simulatorIdOrScenarioName == m_constants.name);
		super.validateSpawnRequest(player, req);
	}
}

private final class TutorialScenarioSpawner: ScenarioSpawner
{
	this(AvailableScenarioConstants constants, Scenario delegate(Simulator sim) factory)
	{
		super(constants, factory);
	}

	override @property ScenarioType scenarioType() const
	{
		return ScenarioType.tutorial;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator);
		assert(req.simulatorIdOrScenarioName == m_constants.name);
		super.validateSpawnRequest(player, req);
	}
}

private final class CampaignScenarioSpawner: ScenarioSpawner
{
	const Campaign* campaign;

	this(AvailableScenarioConstants constants,
		Scenario delegate(Simulator sim) factory, const Campaign* camp)
	{
		super(constants, factory);
		campaign = camp;
	}

	override @property ScenarioType scenarioType() const
	{
		return ScenarioType.campaignMission;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator);
		assert(req.simulatorIdOrScenarioName == m_constants.name);
		super.validateSpawnRequest(player, req);
		// TODO: validate that the previous mission is completed, or this is the
		// first campaign mission.
	}
}

private final class PersistentScenarioSpawner: ScenarioSpawner
{
	private
	{
		Simulator m_simulator;
		Scenario m_scenario;
	}

	@property Simulator simulator() { return m_simulator; }
	@property Scenario scenario() { return m_scenario; }

	this(AvailableScenarioConstants constants,
		Scenario delegate(Simulator sim) factory, string persistentSimId)
	{
		super(constants, factory);
		// eagerly builds the simulator
		m_scenario = createSimulatorAndScenario(persistentSimId);
		m_simulator = scenario.simulator;
		m_simulator.runWithoutPlayers = true;
	}

	override @property ScenarioType scenarioType() const
	{
		return ScenarioType.persistentSimulator;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.existingSimulator);
		enforce(req.simulatorIdOrScenarioName == simulator.id);
		super.validateSpawnRequest(player, req);
	}
}


/// Collection of all standalone scenarios, campaigns and persistent scenarios. Responsible
/// for progress persistence, rendering of scenario collection to the client and simulator
/// preparation. Meat of spawn request validation and handling is performed here.
final class ScenarioDatabase
{
	/// All non-perisstent scenarions, indexed by their name.
	private ScenarioSpawner[string] m_spawnableScenarios;

	/// Persistent scenarios, indexed by simulatorId.
	private PersistentScenarioSpawner[string] m_persistentSims;

	/// Build scenario database. Globals.entityDb must be built at this point.
	this()
	{
		m_persistentSims["main_arena"] =
			new PersistentScenarioSpawner(BattleRoyale.getConstants(false),
				sim => new BattleRoyale(sim), "main_arena");

		AvailableScenarioConstants scenConstants = BattleRoyale.getConstants(true);
		StandaloneScenarioSpawner spawner = new StandaloneScenarioSpawner(
			scenConstants, sim => new BattleRoyale(sim));
		m_spawnableScenarios[scenConstants.name] = spawner;
	}

	PersistentScenarioSpawner getPersistentById(string simId)
	{
		return m_persistentSims[simId];
	}

	/// Start scheduling persistent simulators.
	void startPeristentSimulators()
	{
		foreach (PersistentScenarioSpawner spawner; m_persistentSims.byValue)
			Globals.simulators.add(spawner.simulator);
	}

	/// Prepare response for a player that filters out unavailable scenarios.
	immutable(AvailableScenariosRes) getScenarioResForPlayer(Player player)
	{
		AvailableScenariosRes res;
		// all non-campaign missions
		res.scenarios = m_spawnableScenarios.byValue.filter!(
			spawner => spawner.scenarioType != ScenarioType.campaignMission
		).map!((ScenarioSpawner spawner) {
			AvailableScenario preparedScen;
			preparedScen.constants = cast() spawner.constants;
			preparedScen.type = spawner.scenarioType;
			// TODO: set completion flag from db
			preparedScen.completed = false;
			return preparedScen;
		}).array;
		// append persistent simulator scenarios
		res.scenarios ~= m_persistentSims.byValue.map!((ScenarioSpawner spawner) {
			AvailableScenario preparedScen;
			preparedScen.constants = cast() spawner.constants;
			preparedScen.type = ScenarioType.persistentSimulator;
			preparedScen.simulatorId = (cast(PersistentScenarioSpawner) spawner).simulator.id;
			// TODO: player count
			preparedScen.playerCount = 0;
			return preparedScen;
		}).array;
		return cast(immutable) res;
	}

	/// Validate spawn request, create or get persistent simulator.
	Scenario generateScenarioForSpawnReq(Player player, const SpawnReq req)
	{
		ScenarioSpawner spawner;
		Scenario scen;
		final switch (req.type)
		{
			case SpawnRequestType.newSimulator:
				enforce(req.simulatorIdOrScenarioName in m_spawnableScenarios,
					"scenario not found");
				spawner = m_spawnableScenarios[req.simulatorIdOrScenarioName];
				spawner.validateSpawnRequest(player, req);
				scen = spawner.createSimulatorAndScenario();
				break;
			case SpawnRequestType.existingSimulator:
				enforce(req.simulatorIdOrScenarioName in m_persistentSims,
					"simulator not found");
				spawner = m_persistentSims[req.simulatorIdOrScenarioName];
				spawner.validateSpawnRequest(player, req);
				scen = (cast(PersistentScenarioSpawner) spawner).scenario;
				break;
		}
		return scen;
	}
}


/// List of goals that can be synchronized with clients based on object version.
class ScenarioGoalList: VersionedObject
{
	private
	{
		struct GoalVersionPair
		{
			int goalVersion;
			ScenarioGoal goal;
		}

		GoalVersionPair[] m_goals;
	}

	final @property bool allGoalsSuccessfull() const
	{
		return m_goals.all!(a => a.goal.status == ScenarioGoalStatus.success)();
	}

	final @property bool anyGoalFailed() const
	{
		return m_goals.any!(a => a.goal.status == ScenarioGoalStatus.failed)();
	}

	/// Bump own version if child goals have been updated
	void updateVersion()
	{
		bool needBump = false;
		foreach(ref pair; m_goals)
		{
			if (pair.goalVersion != pair.goal.objVersion)
			{
				pair.goalVersion = pair.goal.objVersion;
				needBump = true;
			}
		}
		if (needBump)
			bumpObjVersion();
	}

	void addGoal(ScenarioGoal goal)
	{
		m_goals ~= GoalVersionPair(goal.objVersion, goal);
		bumpObjVersion();
	}

	void removeGoal(ScenarioGoal goal)
	{
		removeFirst!(a => a.goal is goal)(m_goals);
		bumpObjVersion();
	}
}


abstract class ScenarioGoal: VersionedObject
{
	private
	{
		ScenarioGoalStatus m_status;
	}

	final @property ScenarioGoalStatus status() const { return m_status; }

	abstract ScenarioGoal getGoalStruct();

	final void markSuccess()
	{
		if (m_status == ScenarioGoalStatus.unreached)
		{
			m_status = ScenarioGoalStatus.success;
			bumpObjVersion();
		}
	}

	final void markFailed()
	{
		if (m_status == ScenarioGoalStatus.unreached)
		{
			m_status = ScenarioGoalStatus.failed;
			bumpObjVersion();
		}
	}
}


interface IScenarioCondition
{
	bool satisfied();
}


final class AndCondition: IScenarioCondition
{
	private IScenarioCondition left, right;

	this(IScenarioCondition a, IScenarioCondition b)
	{
		left = a;
		right = b;
	}

	override bool satisfied()
	{
		return left.satisfied() && right.satisfied();
	}
}


AndCondition and(IScenarioCondition a, IScenarioCondition b)
{
	return new AndCondition(a, b);
}


final class OrCondition: IScenarioCondition
{
	private IScenarioCondition left, right;

	this(IScenarioCondition a, IScenarioCondition b)
	{
		left = a;
		right = b;
	}

	override bool satisfied()
	{
		return left.satisfied() || right.satisfied();
	}
}


OrCondition or(IScenarioCondition a, IScenarioCondition b)
{
	return new OrCondition(a, b);
}


enum Comparator: ubyte
{
	less,
	greaterOrEqual
}


/// Distance between two objects that have transforms
final class DistanceCondition: IScenarioCondition
{
	private
	{
		IHasTransform* a;
		IHasTransform* b;
		Comparator m_comparator;
		double m_distanceSqr;
	}

	// Pointers to class references because we allow unallocated object
	// bindings.
	this(IHasTransform* obj1, IHasTransform* obj2, Comparator comparator, double distance)
	{
		assert(distance >= 0.0);
		a = obj1;
		b = obj2;
		m_comparator = comparator;
		m_distanceSqr = distance * distance;
	}

	override bool satisfied()
	{
		if (*a is null || *b is null)
			return false;
		double currentDistSqr =
			((*a).transform.wposition - (*b).transform.wposition).squaredLength;
		final switch (m_comparator)
		{
			case (Comparator.less):
				return currentDistSqr < m_distanceSqr;
			case (Comparator.greaterOrEqual):
				return currentDistSqr >= m_distanceSqr;
		}
	}
}


/// Velocity vector magnitude comparison
final class SpeedCondition: IScenarioCondition
{
	private
	{
		IHasRidigBody* obj;
		Comparator m_comparator;
		double m_speedSqr;
	}

	this(IHasRidigBody* obj1, Comparator comparator, double speed)
	{
		assert(speed >= 0.0);
		obj = obj1;
		m_comparator = comparator;
		m_speedSqr = speed * speed;
	}

	override bool satisfied()
	{
		if (*obj)
			return false;
		double currentSpdSqr =
			(*obj).rigidBody.kinet.vel.squaredLength;
		final switch (m_comparator)
		{
			case (Comparator.less):
				return currentSpdSqr < m_speedSqr;
			case (Comparator.greaterOrEqual):
				return currentSpdSqr >= m_speedSqr;
		}
	}
}



/// Thing that computes the condition and runs the delegate once/repeatedly.
final class ScenarioTrigger
{
	private
	{
		// time since first condition satisfaction
		// or since firing in multi-shot trigger.
		usecs_t m_currentDuration = 0;

		// time that must pass in simulator with condition being active
		// to activate the trigger.
		usecs_t m_activationTime;
		// cooldown after re-trigger
		usecs_t m_cooldown;
		bool m_isCondActive;
		bool m_oneShot;
		bool m_isShot;
		void delegate() m_action;
		IScenarioCondition m_condition;
	}

	// oneShot and isShot means that trigger can be discarded
	@property bool oneShot() const { return m_oneShot; }
	@property bool isShot() const { return m_isShot; }

	this(IScenarioCondition condition, void delegate() action,
		bool oneShot = true, usecs_t activationTime = 0,
		usecs_t cooldown = 0)
	{
		m_condition = condition;
		m_action = action;
		m_oneShot = oneShot;
		m_cooldown = cooldown;
		m_activationTime = activationTime;
	}

	/// Returns true if the trigger was actually fired during this call.
	bool process(usecs_t simTimePassed)
	{
		// cooldown logic
		if (m_isShot && !m_oneShot)
		{
			m_currentDuration += simTimePassed;
			if (m_currentDuration >= m_cooldown)
				m_isShot = false;
			else
				return false;
		}
		if (m_condition.satisfied())
		{
			if (!m_isCondActive)
			{
				m_isCondActive = true;
				m_currentDuration = 0;
			}
			else
				m_currentDuration += simTimePassed;
			if (m_currentDuration >= m_activationTime)
			{
				m_isShot = true;
				if (!m_oneShot)
					m_currentDuration = 0;
				m_isCondActive = false;
				m_action();
				return true;
			}
		}
		else
			m_isCondActive = false;
		return false;
	}
}