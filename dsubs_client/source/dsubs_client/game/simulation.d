module dsubs_client.game.simulation;

import std.algorithm;
import std.array;
import std.conv: to;
import std.format;
import std.math;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;
import dsubs_common.math;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.game.cameracontroller;


class SimulatorState
{
	Submarine playerSub;
	CameraController camController;

	// important UI elements
	TextField tgtThrottleField;
	TextField tgtCourseField;
}


/// setup the state of the game itself
void setupSimulationState(Submarine playerSub, bool alreadyHaveSub = false)
{
	Game.clearEntities();

	if (!Game.serverConnection.connected)
	{
		error("Connection was lost, falling back to main menu");
		// TRANSITION TO MAIN MENU
		setupMainMenu();
		return;
	}

	Game.simState = new SimulatorState();
	Game.simState.playerSub = playerSub;
	Game.worldManager.components ~= playerSub;
	Game.worldManager.camCtx.camera.zoom = 10.0;

	Game.serverConnection.onConnectionClosed += (string reason)
	{
		error("Connection was closed, reason: ", reason);
		// TRANSITION TO MAIN MENU
		setupMainMenu();
	};

	// set up submarine coordinate update
	bool camSetOnSub = false;
	Game.serverConnection.onSubKinematicRes += (SubKinematicRes res)
	{
		Game.simState.playerSub.updateKinematics(res.snap);
		if (!camSetOnSub)
		{
			Game.worldManager.camCtx.camera.center = res.snap.position.toGfm;
			camSetOnSub = true;
			if (!alreadyHaveSub)
				updateTgtCourseDisplay(res.snap.rotation);
		}
	};

	// set up camera
	Game.simState.camController = new CameraController();
	Game.worldManager.mouseReceivers ~= Game.simState.camController;

	setupSimulationGui();
}


void updateTgtCourseDisplay(float newTgt)
{
	Game.simState.tgtCourseField.content =
		format("%.1f", -newTgt.courseAngle.rad2dgr);
}

void updateTgtThrottleDisplay(float newTgt)
{
	Game.simState.tgtThrottleField.content =
		format("%.1f", 100.0f * newTgt);
}


private
{
	immutable int TAB_SIZE = 30;
	immutable int BIG_BTN_FONT = 25;
	immutable int BTN_FONT = 20;
	immutable sfColor HINT_COLOR = sfColor(150, 150, 150, 255);
	immutable sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
}

void setupSimulationGui()
{
	Submarine playerSub = Game.simState.playerSub;

	// Tabs at the top of the screen

	Button tacticalTab = builder(new Button()).content("F1 Tactical").
		fontSize(BIG_BTN_FONT).build;
	Button passiveAcTab = builder(new Button()).content("F2 Passive Acoustics").
		fontSize(BIG_BTN_FONT).build;
	Button activeAcTab = builder(new Button()).content("F3 Active Acoustics").
		fontSize(BIG_BTN_FONT).build;

	Div tabDiv = builder(hDiv([
		tacticalTab,
		passiveAcTab,
		activeAcTab
	])).fixedSize(vec2i(1, TAB_SIZE)).backgroundColor(DIV_BCKGROUND).
	backgroundVisible(true).build;

	// Course and speed labels

	Label curCourse = builder(new Label()).content("course: ").
		fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
	Label curSpeed = builder(new Label()).content("speed: ").
		fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

	Game.serverConnection.onSubKinematicRes += (SubKinematicRes res)
	{
		// course
		dmutstring cc = curCourse.content;
		mutsformat!"course: %.1f"(cc, -res.snap.rotation.courseAngle.rad2dgr);
		curCourse.content = cc;
		// speed
		cc = curSpeed.content;
		vec2d vel = cast(vec2d) res.snap.velocity;
		vec2d fwd = courseVector(res.snap.rotation);
		double proj = dot(vel, fwd);
		mutsformat!"speed: %.1f"(cc, proj);
		curSpeed.content = cc;
	};

	// course and throttle setters

	Label tgtCourseLbl = builder(new Label()).content("tgt course (deg):").
		fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
	Label tgtThrottleLbl = builder(new Label()).content("tgt throttle (%):").
		fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

	static bool numericSymbFilter(dchar c)
	{
		if (c >= '0' && c <= '9' || c == '.' || c == '-')
			return true;
		return false;
	}

	TextField tgtCourseField = builder(new TextField()).
		content(format("%.1f", -playerSub.targetCourse.courseAngle.rad2dgr)).
		symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;
	TextField tgtThrottleField = builder(new TextField()).
		content(format("%.1f", 100.0f * playerSub.targetThrottle)).
		symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;

	void trySendTgtCourse()
	{
		try
		{
			float newTgt = tgtCourseField.content[0..$-1].to!float;
			if (isNaN(newTgt))
				throw new Exception("cheaky cunt");
			immutable CourseReq req = CourseReq(-dgr2rad(newTgt));
			Game.serverConnection.sendMessage(&req);
		}
		catch (Exception e)
		{
			error(e.msg);
			tgtCourseField.content = "0";
		}
	}

	void trySendTgtThrottle()
	{
		try
		{
			float newTgt = tgtThrottleField.content[0..$-1].to!float;
			if (isNaN(newTgt))
				throw new Exception("cheaky cunt");
			if (newTgt > 100.0f)
			{
				tgtThrottleField.content = "100";
				newTgt = 100.0f;
			}
			if (newTgt < -100.0f)
			{
				tgtThrottleField.content = "-100";
				newTgt = -100.0f;
			}
			newTgt /= 100.0f;
			immutable ThrottleReq req = ThrottleReq(newTgt);
			Game.serverConnection.sendMessage(&req);
			playerSub.targetThrottle = newTgt;
		}
		catch (Exception e)
		{
			error(e.msg);
			tgtThrottleField.content = "0";
		}
	}

	tgtCourseField.onKeyPressed += (evt)
	{
		if (evt.code == sfKeyReturn)
			trySendTgtCourse();
	};

	tgtThrottleField.onKeyPressed += (evt)
	{
		if (evt.code == sfKeyReturn)
			trySendTgtThrottle();
	};

	Game.simState.tgtCourseField = tgtCourseField;
	Game.simState.tgtThrottleField = tgtThrottleField;

	Div bottomDiv = builder(
		hDiv(
			[
				builder(
						vDiv([curCourse, curSpeed])
					).fixedSize(vec2i(150, 1)).build,
				builder(
						vDiv([tgtCourseLbl, tgtThrottleLbl])
					).fixedSize(vec2i(180, 1)).build,
				builder(
						vDiv([tgtCourseField, tgtThrottleField])
					).fixedSize(vec2i(65, 1)).build
			])
		).fixedSize(vec2i(1, (BTN_FONT + 6) * 2)).
		backgroundColor(DIV_BCKGROUND).backgroundVisible(true).build;

	Div topLevelDiv = builder(vDiv([
		tabDiv,
		filler,
		bottomDiv
	])).build;

	Game.guiManager.addPanel(new Panel(topLevelDiv));
}