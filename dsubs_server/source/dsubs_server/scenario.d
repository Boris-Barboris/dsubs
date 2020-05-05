module dsubs_server.scenario;

import std.algorithm;
import std.array: array;
import std.random: uniform, uniform01;
import std.range: walkLength;
import std.container.rbtree;
import std.datetime.systime;

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

	void runActions(usecs_t worldTime)
	{
		auto toRun = m_events.lowerBound(AlarmClockAction(worldTime));
		foreach (AlarmClockAction evt; toRun)
			evt.action();
		m_events.remove(toRun);
	}
}


class ScenarioFactory
{
	private
	{
		AvailableScenarioConstants m_contsants;
		Scenario delegate(Simulator sim) m_generator;
	}

	this(AvailableScenarioConstants contsants,
		Scenario delegate(Simulator sim) generator)
	{
		m_contsants = constants;
		m_generator = generator;
	}

	// publicly-visible information.
	@property ref const AvailableScenarioConstants constants() const
	{
		return m_contsants;
	}

	Scenario build(Simulator sim) const
	{
		Scenario res = m_generator(sim);
		res.m_factory = this;
		return res;
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

	/// Throws if some titles are not allowed by the scenario.
	void validateSpawnRequest(Player player, const SpawnReq req)
	{
		const EntityDbShort allowedTitles = m_factory.constants.allowedEntities;
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

	/// Scenario is responsible for generating initial overlay state and briefing
	/// for (re)connecting player.
	abstract void generateBriefing(Player player, out MapElement[] mapOverlayEls,
		out ChatMessage briefing);
}


int intUnixTime()
{
	return Clock.currTime.toUnixTime.to!int;
}


/// Collection of all standalone scenarios, campaigns and persistent scenarios.
final class ScenarioDatabase
{
	private ScenarioFactory[string] m_scenarios;
	private Simulator[string] m_persistentSims;

	const ScenarioFactory getFactory(string scenarioName) const
	{
		enforce(scenarioName in m_scenarios);
		return m_scenarios[scenarioName];
	}

	/// Build scenario database. Globals.entityDb must be built at this point.
	this()
	{
		ScenarioFactory factory = BattleRoyale.getFactory();
		m_scenarios[factory.constants.name] = factory;
	}

	/// Build and schedule persistent simulators.
	void startPeristentSimulators() const
	{
		Simulator sim = new Simulator("main_arena");
		getFactory("Battle royale").build(sim);
		m_persistentSims[sim.id] = sim;
		Globals.simulators.add(sim);
	}

	/// Throws if scenario is not available for the player.
	void validateSpawnRequest(Player p, const SpawnReq req) const
	{
		// TODO
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