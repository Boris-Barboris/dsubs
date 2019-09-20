module dsubs_client.game.states.simulation;

import std.algorithm;
import std.array;
import std.datetime: unixTimeToStdTime, DateTime, SysTime;
import std.format;

import core.time;

import derelict.sfml2.window;
import derelict.sfml2.graphics: sfColor;

import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.hotkeymanager;
import dsubs_client.game.gamestate;
import dsubs_client.game.entities;
import dsubs_client.game.states.mainmenu;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.tacoverlay;
import dsubs_client.game.contacts;
import dsubs_client.game.waterfall;
import dsubs_client.game.sonardisp;
import dsubs_client.game.tubeui;
import dsubs_client.lib.openal;


final class SimulatorState: GameState
{
	this(CICReconnectStateRes recState)
	{
		this.m_recState = recState;
	}

	private
	{
		CICReconnectStateRes m_recState;
	}

	mixin Readonly!(Submarine, "playerSub");
	mixin Readonly!(CameraController, "camController");
	mixin Readonly!(SimulationGUI, "gui");
	mixin Readonly!(StreamingSoundSource, "sonarSound");
	mixin Readonly!(usecs_t, "lastServerTime");
	mixin Readonly!(ContactOverlayShapeCahe, "contactOverlayShapeCache");
	mixin Readonly!(ClientContactManager, "contactManager");
	mixin Readonly!(TacticalOverlay, "tacticalOverlay");
	mixin Readonly!(PlayerSubIcon, "playerSubIcon");

	private MonoTime m_lastServerTimeOnClient;

	@property MonoTime lastServerTimeOnClient() const { return m_lastServerTimeOnClient; }

	@property usecs_t extrapolatedServerTime() const
	{
		return m_lastServerTime +
			max(0, (Game.render.frameStartTime -
				Game.simState.lastServerTimeOnClient).total!"usecs");
	}

	override void setup()
	{
		ReconnectStateRes rawRecState = m_recState.rawState;

		// create submarine
		m_playerSub = new Submarine(
			Game.entityManager, rawRecState.submarineName, rawRecState.propulsorName);
		m_playerSub.targetCourse = rawRecState.targetCourse;
		m_playerSub.targetThrottle = rawRecState.targetThrottle;
		m_playerSub.updateKinematics(rawRecState.subSnap);
		Game.worldManager.components ~= m_playerSub;

		// set up camera
		Game.worldManager.camCtx.camera.center = rawRecState.subSnap.position;
		Game.worldManager.camCtx.camera.zoom = 10.0;
		m_camController = new CameraController(Game.worldManager.camCtx.camera);

		// set tactical overlay
		m_tacticalOverlay = new TacticalOverlay(m_camController);
		Game.guiManager.addPanel(new Panel(m_tacticalOverlay));
		m_playerSubIcon = new PlayerSubIcon(m_tacticalOverlay, m_playerSub);
		m_tacticalOverlay.updateScenarioElements(rawRecState.mapElements);

		m_gui = new SimulationGUI();
		m_gui.waterfall.listenDir = rawRecState.listenDirs[0];
		m_gui.handleSubKinematicRes(cast(CICSubKinematicRes) rawRecState.subSnap);
		m_gui.handleChatMessage(rawRecState.briefing);

		// ammo room and tube initialization
		foreach (AmmoRoomFullState roomState; rawRecState.ammoRoomStates)
			m_playerSub.ammoRoom(roomState.roomId).updateFromFullState(roomState);
		foreach (TubeFullState tubeState; rawRecState.tubeStates)
			m_playerSub.tube(tubeState.tubeId).updateFromFullState(tubeState);

		m_sonarSound = new StreamingSoundSource();
		m_contactOverlayShapeCache = new ContactOverlayShapeCahe();
		m_contactManager = new ClientContactManager(m_recState, m_playerSub.tmpl.hydrophones.length.to!int);
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new MainMenuState();
	}

	override void handleCICDisconnect()
	{
		error("CIC connection lost");
		Game.activeState = new MainMenuState();
	}

	void updateLastServerTime(usecs_t newTime)
	{
		m_lastServerTime = newTime;
		m_lastServerTimeOnClient = MonoTime.currTime;
	}
}


private
{
	enum int TAB_SIZE = 28;
	enum int BIG_BTN_FONT = 25;
	enum int BTN_FONT = 20;
	enum int MSG_FONT = 16;
}


final class SimulationGUI
{

	private
	{
		Label curCourse, curSpeed;
		TextField tgtCourseField, tgtThrottleField;
		TextBox chatMessageBox;
		WaterfallGui m_passiveGui;
		SonarGui m_sonarGui;
		Div m_topLevelDiv;
		float m_oldSonarGain = 1.0f;
		TubeUI[int] tubeUis;
	}

	@property Waterfall waterfall() { return m_passiveGui.wf; }
	@property SonarDisplay sonardisp() { return m_sonarGui.sonar; }

	void handleSubKinematicRes(CICSubKinematicRes res)
	{
		// course
		curCourse.format!"course: %.1f"(-res.snap.rotation.compassAngle.rad2dgr);
		// speed
		vec2d vel = cast(vec2d) res.snap.velocity;
		vec2d fwd = courseVector(res.snap.rotation);
		double proj = dot(vel, fwd);
		curSpeed.format!"speed: %.2f"(proj);
		// pass to other classes that need it
		m_passiveGui.wf.handleSubKinematicRes(res);
		m_sonarGui.sonar.handleSubKinematicRes(res);
	}

	void handleChatMessage(ChatMessage msg)
	{
		auto stdTime = SysTime(unixTimeToStdTime(msg.sentOnUtc));
		chatMessageBox.content = "[" ~ (cast(DateTime) stdTime).timeOfDay.to!string ~
			"]: " ~ msg.message;
	}

	void updateTgtCourseDisplay(float newTgt)
	{
		tgtCourseField.content = format("%.1f", -newTgt.compassAngle.rad2dgr);
	}

	void updateTgtThrottleDisplay(float newTgt)
	{
		tgtThrottleField.content = format("%.1f", 100.0f * newTgt);
	}

	void handleCICListenDirReq(CICListenDirReq req)
	{
		m_passiveGui.wf.listenDir = req.dir;
	}

	this()
	{
		Submarine playerSub = Game.simState.playerSub;

		// Tabs at the top of the screen

		Button tacticalTab = builder(new Button()).content("F1 Tactical").
			fontSize(BIG_BTN_FONT).build;
		Button psonarTab = builder(new Button()).content("F2 Passive sonar").
			fontSize(BIG_BTN_FONT).build;
		Button asonarTab = builder(new Button()).content("F3 Active sonar").
			fontSize(BIG_BTN_FONT).build;

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF1), ()
		{
			tacticalTab.simulateClick();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF2), ()
		{
			psonarTab.simulateClick();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF3), ()
		{
			asonarTab.simulateClick();
		});

		Div tabDiv = builder(hDiv([
			tacticalTab,
			psonarTab,
			asonarTab
		])).fixedSize(vec2i(1, TAB_SIZE)).backgroundColor(COLORS.simPanelBgnd).
			mouseTransparent(false).build;

		// Course and speed labels

		curCourse = builder(new Label()).content("course: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
		curSpeed = builder(new Label()).content("speed: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

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

		tgtCourseField = builder(new TextField()).
			content(format("%.1f", -playerSub.targetCourse.compassAngle.rad2dgr)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;
		tgtThrottleField = builder(new TextField()).
			content(format("%.1f", 100.0f * playerSub.targetThrottle)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;

		void trySendTgtCourse()
		{
			try
			{
				float newTgt = tgtCourseField.content[0..$-1].to!float;
				if (isNaN(newTgt))
					throw new Exception("cheaky cunt, no NaNs");
				auto req = immutable CICCourseReq(-dgr2rad(newTgt));
				Game.ciccon.sendMessage(req);
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
					throw new Exception("cheaky cunt, no NaNs");
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
				trace("setting throttle to: ", newTgt);
				Game.ciccon.sendMessage(immutable CICThrottleReq(newTgt));
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

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyC), ()
		{
			tgtCourseField.requestKbFocus();
			tgtCourseField.selectAll();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyT), ()
		{
			tgtThrottleField.requestKbFocus();
			tgtThrottleField.selectAll();
		});

		chatMessageBox = builder(new TextBox()).fontSize(MSG_FONT).
			fontColor(COLORS.simMessageFont).layoutType(LayoutType.GREEDY).build;

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
						).fixedSize(vec2i(65, 1)).build,
					filler(20),
					chatMessageBox
				])
			).fixedSize(vec2i(1, (BTN_FONT + 6) * 2)).
			backgroundColor(COLORS.simPanelBgnd).mouseTransparent(false).build;

		Div[] tubeUiDivs;
		foreach (Tube tube; playerSub.tubeRange.array.sort!("a.id < b.id"))
		{
			TubeUI ui = new TubeUI(tube);
			tubeUis[tube.id] = ui;
			tubeUiDivs ~= ui.mainDiv;
		}

		GuiElement tabFiller = builder(vDiv([
			filler(),
			builder(hDiv(cast(GuiElement[]) tubeUiDivs)).fixedSize(vec2i(100, 230)).
			borderWidth(8).build
		])).build;
		m_passiveGui = createWaterfallPanel(playerSub.tmpl.hydrophones[0]);
		m_sonarGui = createSonarGui(playerSub.tmpl.sonar);

		m_topLevelDiv = builder(vDiv([
			tabDiv,
			tabFiller,
			bottomDiv
		])).build;

		void setMiddlePane(GuiElement el)
		{
			m_topLevelDiv.setChild(el, 1);
			if (el is tabFiller)
				Game.simState.tacticalOverlay.hidden = false;
			else
				Game.simState.tacticalOverlay.hidden = true;
			Game.inputRouter.clearFocused();
		}

		void saveSoundIfNeeded()
		{
			if (m_topLevelDiv.children[1] is m_passiveGui.root)
			{
				m_oldSonarGain = Game.simState.sonarSound.gain;
				Game.simState.sonarSound.gain = 0.0f;
			}
		}

		void restoreSoundIfNeeded()
		{
			if (m_topLevelDiv.children[1] !is m_passiveGui.root)
				Game.simState.sonarSound.gain = m_oldSonarGain;
		}

		tacticalTab.onClick += ()
		{
			saveSoundIfNeeded();
			setMiddlePane(tabFiller);
		};
		psonarTab.onClick += ()
		{
			restoreSoundIfNeeded();
			setMiddlePane(m_passiveGui.root);
		};
		asonarTab.onClick += ()
		{
			saveSoundIfNeeded();
			setMiddlePane(m_sonarGui.root);
		};

		Game.guiManager.addPanel(new Panel(m_topLevelDiv));
	}
}
