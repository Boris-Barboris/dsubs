module dsubs_server.ai.acoustic;

import std.algorithm: filter;
import std.array: array;

import dsubs_common.math.angles;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;
import dsubs_sound.soundsource: SoundSource;

import dsubs_server.common;
import dsubs_server.globals;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.simulator;
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

	pragma(inline) Simulator simulator() { return m_crew.simulator; }

	private
	{
		AICrew m_crew;
		BehaviourTreeNode m_btRoot;
		BOT_DIFFICULTY m_difficulty;
		int m_ticksPerExecute;
	}

	void execute()
	{
		int ticks = m_ticksPerExecute;
		m_btRoot.execute(ticks);
	}

	private bool isInterestingSignalOwner(Object owner)
	{
		Submarine s = cast(Submarine) owner;
		if (s)
		{
			if (m_crew.side && s.captain && s.captain.side)
			{
				ContactRelation relation = m_crew.side.relateTo(s.captain.side);
				if (relation == ContactRelation.ally)
					return false;
			}
			return true;
		}
		Vessel v = cast(Vessel) owner;
		if (v)
			return true;
		return false;
	}

	private bool isSoundSourceInteresting(SoundSource s)
	{
		return isInterestingSignalOwner(s.owner);
	}

	private bool isReflectorInteresting(Reflector r)
	{
		return isInterestingSignalOwner(r.owner);
	}

	@property bool isTowedArraysUsed() const
	{
		return m_difficulty >= BOT_DIFFICULTY.medium;
	}

	/// Prepare submarine's hydrophones for bot mode
	void prepareSensors()
	{
		// prepare hydrophone filters
		foreach (Hydrophone h; m_crew.submarine.hydrophones)
		{
			h.shouldBeActive = true;
			h.maintainImprints = true;
			h.soundSourceFilter = &isSoundSourceInteresting;
		}
		// prepare active sonar filters
		if (m_crew.submarine.sonar)
		{
			m_crew.submarine.sonar.reflectorFilter = &isReflectorInteresting;
		}
		// if we are not an easy bot, we use towed arrays
		if (m_difficulty >= BOT_DIFFICULTY.medium)
		{
			foreach (wire; m_crew.submarine.rigidBody.wires)
				wire.desiredLength = wire.maxLength * 0.75f;
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
					m_detectionMargin = 4.0f;
					break;
				case (BOT_DIFFICULTY.medium):
					m_detectionMargin = 2.0f;
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
				if (!h.active)
					continue;
				// trace(sub, " acoustic sees: ", h.imprints);
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

		private void pushImprintToCIC(bool isPing)
		{
			Vessel v = cast(Vessel) m_imprintToReport.source.owner;
			assert(v);
			CrewState state = m_crew.state;
			Contact** existingContact = v in state.contacts;
			if (existingContact)
				applyToContact(*existingContact, v, isPing);
			else
			{
				Contact* newCtc = new Contact(v);
				trace("Adding new contact for the source imprint ", m_imprintToReport);
				applyToContact(newCtc, v, isPing);
				state.contacts[v] = newCtc;
			}
		}

		private void applyToContact(Contact* ctc, Vessel v, bool isPing)
		{
			ctc.createdAt = simulator.worldTime;
			if (m_imprintToReport.directionAvailable || isPing)
			{
				ctc.lastHydrophoneData = simulator.worldTime;
				// we boost sonar ping points
				ctc.passiveSonarPoints += max(
					m_imprintToReport.signalLevel.val - m_imprintToReport.backgroundLevel.val,
					isPing ? ClassifyAndTrack.CLASSIFICATION_MARGIN : 0.0f);
				if (isPing)
					classifyAndRelate(ctc, v, m_crew.side);
			}
		}

		private ExecutionResult onRunning(ref int ticks, bool isPing)
		{
			if (isPing || consumeLocalTicks(m_ticksCost, m_ticksLeft, ticks))
			{
				pushImprintToCIC(isPing);
				m_running = false;
				m_ticksLeft = m_ticksCost;
				return ExecutionResult.success;
			}
			return ExecutionResult.running;
		}

		override ExecutionResult execute(ref int ticks)
		{
			if (m_running)
				return onRunning(ticks, false);
			foreach (ref SourceImprint si; m_lastImprints)
			{
				Vessel v = cast(Vessel) si.source.owner;
				assert(v);
				bool isPing = (cast(SonarPing) si.source) !is null;
				if (v && (v !in m_crew.state.contacts || isPing) && !v.dead)
				{
					// not-dead unregistered in contacts not dead vessel sound source
					m_imprintToReport = si;
					m_running = true;
					return onRunning(ticks, isPing);
				}
			}
			return ExecutionResult.success;
		}
	}

	static void classifyAndRelate(Contact* ctc, Vessel v, SideOfConflict ownSide)
	{
		if (ctc.classification != ContactClass.unknown)
			return;
		ContactClass cclass;
		if (cast(Torpedo) v)
		{
			cclass = ContactClass.weapon;
			Torpedo torp = cast(Torpedo) v;
			if (torp.shooterCaptain)
				ctc.relation = ownSide.relateTo(torp.shooterCaptain.side);
		}
		else if (cast(StaticDecoy) v)
			cclass = ContactClass.decoy;
		else if (cast(Submarine) v)
		{
			cclass = ContactClass.submarine;
			// relation is only relevant for submarines.
			Submarine ctcSub = cast(Submarine) v;
			if (ctcSub.captain)
				ctc.relation = ownSide.relateTo(ctcSub.captain.side);
		}
		trace("Classified as ", cclass, ", relation ", ctc.relation,
			" after ", ctc.age, " seconds");
		ctc.classification = cclass;
	}

	private final class ClassifyAndTrack: FixedCostActionNode
	{
		this(string file = __FILE__, size_t line = __LINE__)
		{
			super("Track contacts and classify them", 600, false, file, line);
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
				if (v !in m_crew.state.contacts)
					continue;
				Contact* ctc = m_crew.state.contacts[v];
				bool isPing = (cast(SonarPing) si.source !is null);
				if (!si.directionAvailable && !isPing)
					continue;
				ctc.lastHydrophoneData = simulator.worldTime;
				ctc.passiveSonarPoints += max(
					si.signalLevel.val - si.backgroundLevel.val,
					isPing ? CLASSIFICATION_MARGIN : 0.0f);
				if (ctc.classification == ContactClass.unknown &&
					ctc.passiveSonarPoints > CLASSIFICATION_MARGIN)
				{
					classifyAndRelate(ctc, v, m_crew.side);
				}
			}
			return ExecutionResult.success;
		}
	}

	private BehaviourTreeNode buildEasyBt()
	{
		return new SequenceNode("Acoustic operations", [
			new ReceiveHydrophoneData(),
			new AddNewHydrophoneContact(),
			new ClassifyAndTrack()
		]);
	}
}