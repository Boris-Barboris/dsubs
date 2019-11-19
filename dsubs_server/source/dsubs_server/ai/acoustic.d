module dsubs_server.ai.acoustic;

import std.algorithm: filter;
import std.array: array;

import dsubs_common.math.angles;

import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.torpedo;
import dsubs_server.ai.common;
import dsubs_server.ai.bt;
import dsubs_server.ai.captain;


final class AIAcoustic
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
	}

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
	}

	/// Prepare submarine's hydrophones for bot mode
	void prepareSensors()
	{
		foreach (Hydrophone h; m_crew.submarine.hydrophones)
		{
			h.active = true;
			h.maintainImprints = true;
		}
	}

	private
	{
		/// imprints from the last simulation step
		SourceImprint[] m_lastImprints;
	}

	@property SourceImprint[] lastImprints() { return m_lastImprints; }

	private final class ReceiveHydrophoneData: ActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Receive hydrophones imprints", file, line);
			final switch (m_difficulty)
			{
				case (BOT_DIFFICULTY.easy):
					m_detectionMargin = 10.0f;
					break;
				case (BOT_DIFFICULTY.medium):
					m_detectionMargin = 5.0f;
					break;
				case (BOT_DIFFICULTY.hard):
					m_detectionMargin = 0.0f;
					break;
			}
		}

		private float m_detectionMargin = 0.0f;

		override ExecutionResult execute(ref int ticks)
		{
			Submarine sub = m_crew.submarine;
			m_lastImprints.length = 0;
			foreach (Hydrophone h; sub.hydrophones)
			{
				// trace("Acoustic sees: ", h.imprints);
				m_lastImprints ~= h.imprints.filter!(imp =>
					imp.source.owner &&
					cast(Vessel) imp.source.owner &&			// we are only interested in vessel sounds
					(imp.source.owner !is m_crew.submarine) &&	// and not self-noise
					imp.signalLevel.val - imp.backgroundLevel.val >= m_detectionMargin).array;
			}
			// trace("Acoustic filter accepts: ", m_lastImprints);
			return ExecutionResult.success;
		}
	}

	private final class AddNewHydrophoneContact: ActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Report new hydrophone contact to CIC", file, line);
			m_ticksLeft = m_ticksCost;
		}

		private
		{
			SourceImprint m_imprintToReport;
			int m_ticksLeft;
			int m_ticksCost = 400;
			bool m_running;
		}

		private void pushImprintToCIC()
		{
			Vessel v = cast(Vessel) m_imprintToReport.source.owner;
			assert(v);
			CrewState state = m_crew.state;
			Contact* existingContact = v in state.contacts;
			if (existingContact)
				applyToContact(*existingContact);
			else
			{
				Contact newCtc = Contact(v);
				applyToContact(newCtc);
				state.contacts[v] = newCtc;
			}
		}

		private void applyToContact(ref Contact ctc)
		{
			ctc.createdAt = Globals.sim.worldTime;
			if (m_imprintToReport.directionAvailable)
			{
				ctc.lastHydrophoneData = Globals.sim.worldTime;
				ctc.passiveSonarPoints += m_imprintToReport.signalLevel.val -
					m_imprintToReport.backgroundLevel.val;
			}
		}

		private ExecutionResult onRunning(ref int ticks)
		{
			if (consumeLocalTicks(m_ticksCost, m_ticksLeft, ticks))
			{
				pushImprintToCIC();
				m_running = false;
				m_ticksLeft = m_ticksCost;
				return ExecutionResult.success;
			}
			return ExecutionResult.running;
		}

		override ExecutionResult execute(ref int ticks)
		{
			if (m_running)
				return onRunning(ticks);
			foreach (ref SourceImprint si; m_lastImprints)
			{
				Vessel v = cast(Vessel) si.source.owner;
				assert(v);
				if (v && (v !in m_crew.state.contacts) && !v.dead)
				{
					// not-dead unregistered in contacts not dead vessel sound source
					m_imprintToReport = si;
					m_running = true;
					trace("Queuing new contact for the source imprint ", si);
					return onRunning(ticks);
				}
			}
			return ExecutionResult.success;
		}
	}

	private final class ClassifyAndTrack: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Track contacts and classify them", 1000, file, line);
		}

		enum float CLASSIFICATION_MARGIN = 100.0f;

		override ExecutionResult onTicksConsumed()
		{
			// we go through all imprints and provide ray data to CIC (crew state)
			foreach (ref SourceImprint si; m_lastImprints)
			{
				Vessel v = cast(Vessel) si.source.owner;
				if (v is null)
					continue;
				Contact* ctc = v in m_crew.state.contacts;
				if (ctc is null)
					continue;
				if (!si.directionAvailable)
					continue;
				ctc.lastHydrophoneData = Globals.sim.worldTime;
				ctc.passiveSonarPoints += si.signalLevel.val -
					si.backgroundLevel.val;
				if (ctc.classification == ContactClass.unknown &&
					ctc.passiveSonarPoints > CLASSIFICATION_MARGIN)
				{
					ContactClass cclass;
					if (cast(Torpedo) v)
						cclass = ContactClass.weapon;
					else if (cast(StaticDecoy) v)
						cclass = ContactClass.decoy;
					else if (cast(Submarine) v)
					{
						cclass = ContactClass.submarine;
						// relation is only relevant for submarines.
						Submarine ctcSub = cast(Submarine) v;
						if (ctcSub.captain)
							ctc.relation = m_crew.side.relateTo(ctcSub.captain.side);
					}
					trace(si, " classified as ", cclass, ", after ",
						Globals.sim.worldTime - ctc.createdAt / 1000_000L, " seconds");
					ctc.classification = cclass;
				}
			}
			return ExecutionResult.success;
		}
	}

	private BehavourTreeNode buildEasyBt()
	{
		return new SequenceNode("Acoustic operations", [
			new ReceiveHydrophoneData(),
			new AddNewHydrophoneContact(),
			new ClassifyAndTrack()
		]);
	}
}