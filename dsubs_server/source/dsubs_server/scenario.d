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
		enforce(req.type == SpawnRequestType.newSimulator, "wrong type");
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
			new PersistentScenarioSpawner(BattleRoyale.getConstants(),
				sim => new BattleRoyale(sim), "main_arena");

		AvailableScenarioConstants scenConstants = BattleRoyale.getConstants();
		scenConstants.name = "Circle arena (SP)";
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