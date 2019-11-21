module dsubs_server.ai.helmsman;

import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.ai.common;
import dsubs_server.ai.captain;



enum WhereToSwimType: byte
{
	idle,			/// do not alter desired course
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

enum NavigationSpeed: byte
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

		whereToSwimOrder = OrderQueue!WhereToSwim(1);
		navigationSpeedOrder = OrderQueue!NavigationSpeed(1);
	}

	private
	{
		AICrew m_crew;
		BehavourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;

		// actively implemented orders
		WhereToSwim m_whereToSwim;
		NavigationSpeed m_navigationSpeed;
		float m_desiredThrottle = 0.0f;
	}

	OrderQueue!WhereToSwim whereToSwimOrder;
	OrderQueue!NavigationSpeed navigationSpeedOrder;

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
	}

	private final class ProcessOrder: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Consume last order and move it to active one", 400, false,
				file, line);
		}

		override @property bool shouldBeRunning()
		{
			return whereToSwimOrder.hasOrder || navigationSpeedOrder.hasOrder;
		}

		override ExecutionResult onTicksConsumed()
		{
			if (whereToSwimOrder.hasOrder)
			{
				// trace("whereToSwimOrder order received");
				m_whereToSwim = whereToSwimOrder.popFront();
				return ExecutionResult.success;
			}
			if (navigationSpeedOrder.hasOrder)
			{
				m_navigationSpeed = navigationSpeedOrder.popFront();
				final switch (m_navigationSpeed)
				{
					case NavigationSpeed.stop:
						m_desiredThrottle = 0.0f;
						break;
					case NavigationSpeed.silent:
						m_desiredThrottle = 0.2f;
						break;
					case NavigationSpeed.tactical:
						m_desiredThrottle = 0.45f;
						break;
					case NavigationSpeed.fast:
						m_desiredThrottle = 0.7f;
						break;
					case NavigationSpeed.flank:
						m_desiredThrottle = 1.0f;
						break;
					case NavigationSpeed.random:
						m_desiredThrottle = uniform(0.4f, 0.8f);
						break;
				}
				m_desiredThrottle = m_desiredThrottle.clamp(0.0f, 1.0f);
				// trace("m_desiredThrottle was chosen to ", m_desiredThrottle);
				return ExecutionResult.success;
			}
			return ExecutionResult.failure;
		}
	}

	private final class MaintainCourse: ActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Adjust rudder according to current order", file, line);
		}

		override ExecutionResult execute(ref int ticks)
		{
			assert(ticks > 0);
			final switch (m_whereToSwim.type)
			{
				case WhereToSwimType.idle:
					break;
				case WhereToSwimType.course:
					m_crew.submarine.targetCourse = m_whereToSwim.course;
					break;
				case WhereToSwimType.destination:
					vec2d delta = m_whereToSwim.destination -
						m_crew.submarine.transform.wposition;
					if (delta.length < 100.0)
					{
						trace("Helmsman decides that the destination was reached");
						m_whereToSwim.type = WhereToSwimType.idle;
						m_desiredThrottle = 0.0f;
					}
					if (delta != vec2d(0, 0))
						m_crew.submarine.targetCourse = courseAngle(delta);
					break;
			}
			return ExecutionResult.success;
		}
	}

	private final class MaintainThrottle: ActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Adjust throttle according to current order", file, line);
		}

		override ExecutionResult execute(ref int ticks)
		{
			assert(ticks > 0);
			m_crew.submarine.targetThrottle = m_desiredThrottle;
			return ExecutionResult.success;
		}
	}

	private BehavourTreeNode buildEasyBt()
	{
		return new ParallelNode("Helmsman operations", [
			new ProcessOrder(),
			new MaintainCourse(),
			new MaintainThrottle()
		], 1);
	}
}