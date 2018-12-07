module dsubs_client.game.states.simulation;

import std.algorithm;
import std.array;
import std.format;

import derelict.sfml2.window;

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
import dsubs_client.game.overlay;
import dsubs_client.game.states.simulation.waterfall;
import dsubs_client.game.states.simulation.sonardisp;
import dsubs_client.lib.openal;


final class SimulatorState: GameState
{
	this(CICReconnectStateRes recState)
	{
		super(GameStateKind.SIMULATION);
		this.recState = recState;
	}

	private
	{
		CICReconnectStateRes recState;
	}

	mixin Readonly!(Submarine, "playerSub");
	mixin Readonly!(CameraController, "camController");
	mixin Readonly!(SimulationGUI, "gui");
	mixin Readonly!(StreamingSoundSource, "sonarSound");

	override void setup()
	{
		// create submarine
		m_playerSub = new Submarine(
			Game.entityManager, recState.submarineName, recState.propulsorName);
		m_playerSub.targetCourse = recState.targetCourse;
		m_playerSub.targetThrottle = recState.targetThrottle;
		m_playerSub.updateKinematics(recState.subSnap);
		Game.worldManager.components ~= m_playerSub;

		// set up camera
		Game.worldManager.camCtx.camera.center = recState.subSnap.position.toGfm;
		Game.worldManager.camCtx.camera.zoom = 10.0;
		m_camController = new CameraController();
		Game.worldManager.mouseReceivers ~= m_camController;

		m_gui = new SimulationGUI();
		Game.worldManager.components ~= new PlayerSubIcon(m_playerSub);
		m_gui.hydrophoneGui.listenDir = recState.listenDirs[0];

		m_sonarSound = new StreamingSoundSource();
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
}


private
{
	enum int TAB_SIZE = 28;
	enum int BIG_BTN_FONT = 25;
	enum int BTN_FONT = 20;
	enum sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
	enum sfColor DIV_BORDRCOLOR = sfColor(10, 10, 0, 200);
}


final class SimulationGUI
{

	private
	{
		Label curCourse, curSpeed;
		TextField tgtCourseField, tgtThrottleField;
		Waterfall m_waterfall;
		GuiElement m_passiveGui;
		SonarDisplay m_sonarGui;
		Div m_topLevelDiv;
		float m_oldSonarGain = 1.0f;
	}

	@property Waterfall hydrophoneGui() { return m_waterfall; }
	@property SonarDisplay sonarGui() { return m_sonarGui; }

	void handleSubKinematicRes(CICSubKinematicRes res)
	{
		// course
		dmutstring cc = curCourse.content;
		mutsformat!"course: %.1f"(cc, -res.snap.rotation.compassAngle.rad2dgr);
		curCourse.content = cc;
		// speed
		cc = curSpeed.content;
		vec2d vel = cast(vec2d) res.snap.velocity;
		vec2d fwd = courseVector(res.snap.rotation);
		double proj = dot(vel, fwd);
		mutsformat!"speed: %.1f"(cc, proj);
		curSpeed.content = cc;
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
		m_waterfall.listenDir = req.dir;
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
		])).fixedSize(vec2i(1, TAB_SIZE)).backgroundColor(DIV_BCKGROUND).build;

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
			backgroundColor(DIV_BCKGROUND).build;

		GuiElement tabFiller = filler();
		m_passiveGui = createWaterfallPanel(m_waterfall);
		m_sonarGui = new SonarDisplay(playerSub.tmpl.sonar);

		m_topLevelDiv = builder(vDiv([
			tabDiv,
			tabFiller,
			bottomDiv
		])).build;

		void setMiddlePane(GuiElement el)
		{
			m_topLevelDiv.setChild(el, 1);
			Game.inputRouter.guiRouter.clearMouseCache();
		}

		void saveSoundIfNeeded()
		{
			if (m_topLevelDiv.children[1] is m_passiveGui)
			{
				m_oldSonarGain = Game.simState.sonarSound.gain;
				Game.simState.sonarSound.gain = 0.0f;
			}
		}

		void restoreSoundIfNeeded()
		{
			if (m_topLevelDiv.children[1] !is m_passiveGui)
				Game.simState.sonarSound.gain = m_oldSonarGain;
		}

		tacticalTab.onClick += (btn)
		{
			saveSoundIfNeeded();
			setMiddlePane(tabFiller);
		};
		psonarTab.onClick += (btn)
		{
			restoreSoundIfNeeded();
			setMiddlePane(m_passiveGui);
		};
		asonarTab.onClick += (btn)
		{
			saveSoundIfNeeded();
			setMiddlePane(m_sonarGui);
		};

		Game.guiManager.addPanel(new Panel(m_topLevelDiv));
	}
}