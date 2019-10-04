module dsubs_server.ai.helmsman;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.ai.common;
import dsubs_server.ai.captain;



enum WhereToSwimType
{
	course,			/// hold course
	destination		/// swim to position
}

struct WhereToSwim
{
	WhereToSwimType type;
	union
	{
		vec2d destination;
		double course;
	}
}

enum NavigationSpeed
{
	stop,
	silent,
	tactical,
	fast,
	flank,
	random	// helmsman is to pick a speed of his choosing
}


/**
Throttle and course controller.
*/
final class AIHelmsman
{
	this(AICrew crew, BOT_DIFFICULTY difficulty)
	{
		m_crew = crew;
		m_difficulty = difficulty;
		m_ticksPerExecute = ticksPerDifficulty(m_difficulty);
		m_btRoot = buildEasyBt();
	}

	private
	{
		AICrew m_crew;
		BehavourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;

		// internal state
		WhereToSwim m_whereToSwim;
		NavigationSpeed m_navigationSpeed;
	}

	OrderQueue!WhereToSwim whereToSwimOrder;
	OrderQueue!NavigationSpeed navigationSpeedOrder;

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
	}

	final class SetSpeedSimple: FixedCostActionNode
	{
		this()
		{
			super("Set throttle according to NavigationSpeed", 400);
		}

		private float m_bias;

		override ExecutionResult onTicksConsumed()
		{
			float throttle;
			final switch (m_crew.state.helmsmanOrder.speed)
			{
				case NavigationSpeed.stop:
					throttle = 0.0f;
					break;
				case NavigationSpeed.silent:
					throttle = 0.2f;
					break;
				case NavigationSpeed.tactical:
					throttle = 0.4f;
					break;
				case NavigationSpeed.fast:
					throttle = 0.7f;
					break;
				case NavigationSpeed.flank:
					throttle = 1.0f;
					break;
				case NavigationSpeed.random:
					throttle = uniform(0.25f, 0.8f);
					break;
			}
			throttle.clamp(0.0f, 1.0f);
			m_crew.submarine.targetThrottle = throttle;
			return ExecutionResult.success;
		}
	}

	private BehavourTreeNode buildEasyBt()
	{
		return new ParallelNode("Helmsman simultaneous rudder and thrust control", [
			new FallbackNode("Course control", [
				new SequenceNode("Set rudder course in case of course order", [
					new ConditionNode("Is it a course order?"),
					new NopAction("Set rudder course from course order")
				]),
				new SequenceNode("Set rudder course in case of destination order", [
					new ConditionNode("Is it a destination order?"),
					new NopAction("Set rudder course towards destination")
				])
			]),
			new SetSpeedSimple()
		]);
	}
}