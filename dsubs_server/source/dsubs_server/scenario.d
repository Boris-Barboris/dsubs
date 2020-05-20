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


/// Running instance of scenario with all necessary internal state.
abstract class Scenario
{
	protected Simulator m_simulator;
	protected ScenarioFactory m_factory;

	final @property Simulator simulator() { return m_simulator; }
	final @property ScenarioFactory factory() { return m_factory; }

	/// Scenario can only be instantiated for a simulator. Binding is eager.
	this(Simulator sim)
	{
		assert(sim);
		m_simulator = rhs;
		m_simulator.scenario = this;
	}

	abstract void onBeforeSimulation();

	abstract void onAfterSimulation();

	/// Scenario is responsible for picking true world-space player spawn position.
	abstract void selectPlayerSpawnPosition(Player player,
		out vec2d position, out double rotation);

	/// Scenario is responsible for generating initial overlay state and briefing
	/// for (re)connecting player.
	abstract void generateBriefing(Player player, out MapElement[] mapOverlayEls,
		out ChatMessage briefing);
}


private final class ScenarioFactory
{
	private
	{
		AvailableScenarioConstants m_contsants;
		Scenario delegate(Simulator sim) m_factory;
	}

	this(AvailableScenarioConstants contsants,
		Scenario delegate(Simulator sim) factory)
	{
		m_contsants = constants;
		m_factory = factory;
	}

	// publicly-visible information.
	@property ref const AvailableScenarioConstants constants() const
	{
		return m_contsants;
	}

	Scenario build(Simulator sim) const
	{
		Scenario res = m_factory(sim);
		res.m_factory = this;
		return res;
	}

	/// Throws if some modules/subs are not allowed by the scenario.
	void validateSpawnRequest(Player player, const SpawnReq req)
	{
		const EntityDbShort allowedTitles = m_constants.allowedEntities;
		enforce(canFind(allowedTitles.controllableSubNames, req.submarineName));
		enforce(canFind(allowedTitles.propulsorNames, req.propulsorName));
		foreach (const TubeSpawnState ltl; req.loadableTubeLoadouts)
			if (ltl.loadedWeapon)
				enforce(canFind(allowedTitles.weaponNames, ltl.loadedWeapon));
		foreach (const AmmoRoomFullState arl; req.ammoRoomLoadouts)
		{
			foreach (const WeaponCount wc; arl.storedWeapons)
				enforce(canFind(allowedTitles.weaponNames, wc.weaponName));
		}
	}
}


private struct Campaign
{
	string name;
	string description;
	CampaignScenarioSpawner[] scenarios;
}

/// Scenario can be a persistent-sim, standalone or part of a campaign.
/// Various checks must be performed by the server to ensure spawn request validity.
private abstract class ScenarioSpawner
{
	protected ScenarioFactory m_factory;

	final @property const(ScenarioFactory) factory() const
	{
		return m_factory;
	}

	this(ScenarioFactory factory)
	{
		m_factory = factory;
	}

	@property ScenarioType scenarioType() const;

	/// Throws if something is wrong.
	void validateSpawnRequest(Player player, const SpawnReq req)
	{
		m_factory.validateSpawnRequest(player, req);
	}

	Scenario createSimulatorAndScenario(string simId = null)
	{
		if (simId == null)
			simId = randomUUID().toString();
		Simulator sim = new Simulator(simId);
		Scenario res = m_factory.build(sim);
		return res;
	}
}


private final class StandaloneScenarioSpawner: ScenarioSpawner
{
	this(ScenarioFactory factory) { super(factory); }

	@override @property ScenarioType scenarioType() const
	{
		return ScenarioType.standalone;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator, "wrong type");
		assert(req.simulatorIdOrScenarioName == m_factory.m_contsants.name);
		super.validateSpawnRequest(player, req);
	}
}

private final class TutorialScenarioSpawner: ScenarioSpawner
{
	this(ScenarioFactory factory) { super(factory); }

	@override @property ScenarioType scenarioType() const
	{
		return ScenarioType.tutorial;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator);
		assert(req.simulatorIdOrScenarioName == m_factory.m_contsants.name);
		super.validateSpawnRequest(player, req);
	}
}

private final class CampaignScenarioSpawner: ScenarioSpawner
{
	Campaign* campaign;

	this(ScenarioFactory factory, Campaign camp)
	{
		super(factory);
		campaign = camp;
	}

	@override @property ScenarioType scenarioType() const
	{
		return ScenarioType.campaignMission;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.newSimulator);
		assert(req.simulatorIdOrScenarioName == m_factory.m_contsants.name);
		super.validateSpawnRequest(player, req);
		// TODO: validate that the previous mission is completed, or this is the
		// first campaign mission.
	}
}

private final class PersistentScenarioSpawner: ScenarioSpawner
{
	Simulator simulator;
	Scenario scenario;

	// eagerly builds the simulator
	this(ScenarioFactory factory, string persistentSimId)
	{
		super(factory);
		scenario = createSimulatorAndScenario(persistentSimId);
		simulator = scenario.simulator;
	}

	@override @property ScenarioType scenarioType() const
	{
		return ScenarioType.campaignMission;
	}

	override void validateSpawnRequest(Player player, const SpawnReq req)
	{
		enforce(req.type == SpawnRequestType.existingSimulator);
		enforce(req.simulatorIdOrScenarioName == simulator.id);
		super.validateSpawnRequest(player, req);
		// TODO: validate that the previous mission is completed, or this is the
		// first campaign mission.
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
			new PersistentScenarioSpawner(BattleRoyale.getFactory(), "main_arena");
		ScenarioFactory singleBrFactory = BattleRoyale.getFactory();
		singleBrFactory.m_contsants.name = "Battle royale (singleplayer)";
		m_spawnableScenarios[singleBrFactory.m_contsants.name] =
			new StandaloneScenarioSpawner(singleBrFactory);
	}

	/// Start scheduling persistent simulators.
	void startPeristentSimulators() const
	{
		foreach (PersistentScenarioSpawner spawner; m_persistentSims.byValue)
			Globals.simulators.add(spawner.simulator);
	}

	/// Prepare response for a player that filters out unavailable scenarios.
	AvailableScenariosRes getScenarioResForPlayer(Player p) const
	{
		AvailableScenariosRes res;
		res.scenarios = m_scenarios.byValue.map!((ScenarioFactory factory) {
			AvailableScenario preparedScen;
			preparedScen.constants = factory.constants;
			preparedScen.type = ScenarioType.standalone;
			// TODO
			preparedScen.completed = false;
			return preparedScen;
		}).array;
		// append persistent simulator scenarios
		res.scenarios ~= m_persistentSims.byValue.map!((Simulator sim) {
			AvailableScenario preparedScen;
			preparedScen.constants = sim.scenario.factory.constants;
			preparedScen.type = ScenarioType.persistentSimulator;
			preparedScen.simulatorId = sim.id;
			// TODO
			preparedScen.completed = false;
			return preparedScen;
		}).array;
		return res;
	}
}