module dsubs_server.ai.captain;


import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.weaponry;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.ai.common;



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
		string m_name;
		BOT_DIFFICULTY m_difficulty;
		CrewState m_state;
	}

	final @property CrewState state() { return m_state; }

	override @property void submarine(Submarine rhs)
	{
		super(rhs);
		// we need to build the officers according to submarine capabilities and
		// bot difficulty.
		m_captain = new AICaptain(this, m_difficulty);
	}

	void afterSimulation()
	{
		if (m_submarine is null || m_submarine.dead)
			return;
		if (m_captain)
			m_captain.execute();
	}
}

/// Strongly-typed blackboard
final class CrewState
{
	/// world-space destination.
	vec2d* destination;
	Contact[] contacts;
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
	return sub.tubeCount > 0;
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
		SubmarineFactory subFac = Globals.entityDb.getSubmarineFactory(m_crew.submarine.prototypeName);
		if (subFac.isCombatCapable)
		{
			rootFallbackNodes ~= new SequenceNode("Attack if target visible", [
				new ConditionNode("Have ammo", null),
				new ConditionNode("Any target visible and solution ready", null),
				new FallbackNode("Approach and attack closest target", [
						new SequenceNode("Approach target if needed", [
							new ConditionNode("Closest target too far"),
							new NopAction("Approach closest target")
						]),
						new NopAction("Attack closest target")
					]),
				]);
		}
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