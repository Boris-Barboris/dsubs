module dsubs_server.scenarios.tutorials.hydrophonetutorial;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.simulator;


final class HydrophoneTmaTutorial: SinglePlayerScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "Hydrophones";
		constants.shortDescription = "Learn to use the hydrophone.";
		constants.fullDescription =
`Hydrophone is a sensor that listens to the sea around it. It can be used to detect and classify submarines, animals, torpedoes and any other noise sources. It's advantage over active sonar is it's stealthiness. It's disadvantage is the lack of range measurement capability: you only know the bearing of the sound source, not the distance.

This tutorial explains hydrophone waterfall display functionality, towed hydrophone arrays and some advanced TMA techniques: contact merging, trimming, triangulation.

You pass the test when you can shadow the target by only using your hydrophones.`;
		constants.allowedEntities = EntityDbShort(["Stork"], ["Seven-blade screw"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to active sonar tutorial"));
		m_victoryLongReport =
		`You now know how to use hydrophones to gain an edge on your enemy.`;

		SimpleGoal shadowGoal = new SimpleGoal("Shadow the target for 1 minute",
`Detect the target using hydrophones. Stay at most 100m away from the target for 1 minute.`);
		addVisibleGoal(shadowGoal);
		SimpleGoal noPingGoal =
			new SimpleGoal("Do not use active sonar",
				"Active sonar is forbidden.", "Active sonar is forbidden.");
		addVisibleGoal(noPingGoal);

		AICrew crew = new AICrew(BOT_DIFFICULTY.medium);
		SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
		Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
		botSub.transform.position = vec2d(-2300.0, 1000.0);
		botSub.transform.rotation = dgr2rad(-20);
		m_simulator.bots.registerEntity(crew);
		crew.goal = new SwimToDestinationGoal(crew, vec2d(2000.0, 30000.0));
		botSub.register(m_simulator);

		ScenarioTrigger shadowTrigger = new ScenarioTrigger(
			new DistanceCondition(
				{ return m_playerSub.transform; },
				{ return botSub.transform; },
				Comparator.less, 100.0),
			{ shadowGoal.markSuccess(); noPingGoal.markSuccess(); },
			true, 60_000_000L);
		addTrigger(shadowTrigger);

		ScenarioTrigger playerPingsTrigger = new ScenarioTrigger(
			new SubPingsCondition(
				{ return m_playerSub; }, sim),
			{ noPingGoal.markFailed(); });
		addTrigger(playerPingsTrigger);

		// text hints
		m_syncState.mapElements.addElement("zoomhint",
			MapElement.text(MapText(
				vec2d(10, 0), 16), COLOR_HINT,
				"zoom out for more hints"));
		m_syncState.mapElements.addElement("hydrophone",
			MapElement.text(MapText(
				vec2d(600, 1000), 14), COLOR_HINT,
`Press F2 to enter bow hydrophone 'waterfall' screen. Black & white
image that flows down is a panoramic visualization of the intensity
of surrounding noise. Louder sound sources are brighter, silence is black.
Mouse zoom and panning works, just like in other panels.

Around bearing 290 the test target should already be emitting strong
screw-generated noise. Listen to it by left-clicking withing the bright
noise trail. White inverted triangle in the header of the waterfall display
should move to the bearing you've clicked on. This is a 'beamforming'
director. You can only listen to the sound from one beam per hydrophone.

Adjust the volume in left upper corner to the comfortable level.
Note the patterns in the target noise. It is a trader vessel with one
3-bladed propeller. Each third beat is louder than the other two.
This, and the tone of the noise are main ways to classify the target
using just your ears.

Notice the small vertical grey line above the target's noise trail in
the header of the waterfall display. This is a 'noise peak' that can
be 'tracked' to continiously generate ray samples, that are valuable
for TMA. Right-click on the 'noise peak' (not on the noise trail,
but on the black header above it, on the short grey line) and
select 'new tracker'. Verify that the new contact was created
on tactical map (F1). Try dragging the tracker with left mouse
button on the waterfall screen, disassociate it from the peak,
observe it becoming grey, then drag it back to peak to reactivate
it. This can be used to recover the tracker after the loss of
contact.

Let the tracker run for a minute. Enter TMA mode and look at the
green rays that start at your bow and go North-West. These are
hydrophone ray samples. They help with TMA, but provide very
imprecise data. They have to be combined with other sources of
information to provide a good solution.

On the F1 screen notice the 'towed array' slider right from
the tube controls. Drag it to the right and set thrust to 40%.
After a while the towed hydrophone will start to extend. Go to it's
screen (F3) and repeat the tracker assignment procedure on the
target. Note the mirroring of the target signal on East, caused
by the shape of towed array acoustic antennae. Each signal has a
mirror 'ghost'.

Go to F1 map. You now should see two separate contacts from two
different hydrophones. Right click on any of the two and select
'merge', then left-click on the second one. Now the trackers will
generate ray data in synchrony. Let the trackers do their job
for 2-10 minutes. You can now perform a more accurate TMA, because
the contact database can triangulate using ray intersections from
two hydrophones. Triangulation can be turned off by right-clicking
on contact and selecting 'toggle ray intersect'.

Right-click the contact, select 'trim to last' and select 30s.
This will remove all but the last 30 seconds of data points
(rays, positions etc) from the contact.
This can be used to declutter the TMA visual.

Also note that you can create single-ray contacts from waterfall
diplay without a tracker. Just right-click on the blip that has
attracted your attention and select 'new contact'.

Good way to improve the precision of the solution is to relocate
your submarine. Sprint forward for a minute or two, slow down
and continue observations. Don't forget to reconnect trackers to
the peaks.

Once you are confident with the solution, perform the shadowing
maneuver that is stated in the objective.`));
	}
}