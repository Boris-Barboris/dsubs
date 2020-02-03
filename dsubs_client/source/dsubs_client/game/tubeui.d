module dsubs_client.game.tubeui;

import std.algorithm: map, canFind;
import std.algorithm.comparison: min, max;
import std.format;

import core.time: MonoTime;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game;
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;
import dsubs_client.game.tacoverlay;



private
{
	enum int FONT = 12;
	enum int LAUNCH_FONT = 15;
	enum int AIM_BLOCK_HEIGHT = 120;
}


final class TubeUI
{
	private
	{
		Tube m_tube;
		Div m_mainDiv;

		// aim seciton
		Div m_aimDiv;
		GuiElement m_aimFiller;
		bool m_aiming;
		WeaponProjectionTrace m_overlayTrace;
		WeaponAimHandle m_overlayHandle;

		// main section
		GuiElement m_aimElement;
		Button m_aimButton;
		Button[TubeState.open + 1] m_desiredStateButtons;
		Button m_launchButton;
		Label m_currentStateLabel;
		Button m_weaponButton;
		Label m_tubeNameLabel;
	}

	@property Div mainDiv() { return m_mainDiv; }

	this(Tube tube)
	{
		m_tube = tube;

		m_tubeNameLabel = builder(new Label()).content("tube " ~ (m_tube.id + 1).to!string).
			fontSize(FONT).build;
		m_weaponButton = builder(new Button()).fontSize(FONT).build;
		m_currentStateLabel = builder(new Label()).fontSize(FONT).build;
		if (m_tube.tubeType == TubeType.standard)
		{
			m_aimButton = builder(new Button()).content("Aim").
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			m_aimButton.onClick += &onAimButtonClick;
			m_aimElement = m_aimButton;
		}
		else
			m_aimElement = filler();
		m_launchButton = builder(new Button()).content("Launch").
			fontColor(COLORS.simButtonDisabledFont).fontSize(LAUNCH_FONT).
			backgroundColor(COLORS.simButtonDisabledBgnd).build;
		m_desiredStateButtons[TubeState.dry] =
			builder(new Button()).content("D").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;
		m_desiredStateButtons[TubeState.flooded] =
			builder(new Button()).content("F").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;
		m_desiredStateButtons[TubeState.open] =
			builder(new Button()).content("O").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;

		Div desiredStateDiv = builder(hDiv(cast(GuiElement[]) m_desiredStateButtons[])).
			fixedSize(vec2i(100, LAUNCH_FONT + 4)).borderWidth(4).build;

		m_aimFiller = filler(AIM_BLOCK_HEIGHT);

		m_mainDiv = builder(vDiv([
			m_aimFiller,
			m_tubeNameLabel,
			m_aimElement,
			m_launchButton,
			desiredStateDiv,
			m_currentStateLabel,
			m_weaponButton])).borderWidth(4).fixedSize(vec2i(80, AIM_BLOCK_HEIGHT + 95)).build;

		// now we bind updates
		m_tube.onStateUpdate += &updateFromTube;
		m_launchButton.onClick += &m_tube.sendLaunchRequest;
		m_weaponButton.onClick += &createSelectWeaponContextMenu;
		for (TubeState state = TubeState.dry; state <= TubeState.open; state++)
		{
			Button btn = m_desiredStateButtons[state];
			btn.onClick += (newState) {
				return () { m_tube.sendDesiredStateRequest(newState); };
			} (state);
		}
	}

	void updateFromTube(Tube t)
	{
		assert(t is m_tube);
		updateWeaponContent();
		// update state label
		m_currentStateLabel.content = m_tube.currentState.to!string;
		updateDesiredStateButtons();
		updateLaunchButton();
	}

	private void onAimButtonClick()
	{
		if (!m_aiming && m_tube.loadedWeapon)
		{
			m_aimButton.content = "Stop aiming";
			buildAimDiv();
			m_mainDiv.setChild(m_aimDiv, 0);
			// build trace overlay
			m_overlayTrace = new WeaponProjectionTrace(
				Game.simState.tacticalOverlay, m_tube);
			m_overlayHandle = new WeaponAimHandle(
				Game.simState.tacticalOverlay, m_tube, this);
		}
		else
		{
			m_aimButton.content = "Aim";
			m_mainDiv.setChild(m_aimFiller, 0);
			if (m_overlayTrace)
			{
				Game.simState.tacticalOverlay.remove(m_overlayTrace);
				m_overlayTrace = null;
			}
			if (m_overlayHandle)
			{
				Game.simState.tacticalOverlay.remove(m_overlayHandle);
				m_overlayHandle = null;
			}
		}
		m_aiming = !m_aiming;
	}

	private
	{
		TextField m_courseTextField;
		TextField m_activationRangeField;
	}

	void updateAimFieldsFromTube()
	{
		string marchCourseContent;
		WeaponParamValue* wpv = WeaponParamType.marchCourse in m_tube.weaponParams;
		if (wpv)
			marchCourseContent = format("%.1f", -wpv.course.compassAngle.rad2dgr);
		m_courseTextField.content = marchCourseContent;
		string activationRangeContent = format("%.0f",
			m_tube.weaponParams[WeaponParamType.activationRange].range);
		m_activationRangeField.content = activationRangeContent;
	}

	private void buildAimDiv()
	{
		// build m_aimDiv
		Label courseLabel = builder(new Label()).content("course ").
			fontSize(FONT).fixedSize(vec2i(45, 1)).build;
		m_courseTextField = builder(new TextField()).symbolFilter(&numericSymbFilter).
			fontSize(FONT).build;
		m_courseTextField.onKeyReleased += (k) {
			if (m_courseTextField.content.length == 1)
			{
				m_tube.weaponParams.remove(WeaponParamType.marchCourse);
				m_tube.weaponParams.remove(WeaponParamType.activeCourse);
			}
			else
			{
				try
				{
					float newTgt = m_courseTextField.content[0..$-1].to!float;
					if (!isNaN(newTgt))
					{
						float radTgt = -newTgt.dgr2rad;
						m_tube.marchCourse = radTgt;
						m_tube.activeCourse = radTgt;
					}
				}
				catch (Exception e) {}
			}
		};

		Label activationRangeLabel = builder(new Label()).content("RTE(m) ").
			fontSize(FONT).fixedSize(vec2i(45, 1)).build;
		m_activationRangeField = builder(new TextField()).
			symbolFilter(&numericSymbFilter).fontSize(FONT).build;
		m_activationRangeField.onKeyReleased += (k) {
			try
			{
				float rawTgt = m_activationRangeField.content[0..$-1].to!float;
				if (!isNaN(rawTgt))
				{
					float clampedTgt = max(m_tube.activationRangeLimits.min, rawTgt);
					clampedTgt = min(m_tube.activationRangeLimits.max, clampedTgt);
					m_tube.activationRange = clampedTgt;
					if (rawTgt < clampedTgt && rawTgt >= 0.0f)
						m_activationRangeField.content = format("%.0f", rawTgt);
					else
						m_activationRangeField.content = format("%.0f", clampedTgt);
				}
			}
			catch (Exception e) {}
		};
		m_activationRangeField.onKbFocusLoss += ()
		{
			m_activationRangeField.content = format("%.0f",
				m_tube.weaponParams[WeaponParamType.activationRange].range);
		};

		Label marchSpeedLabel = builder(new Label()).content("RTE spd ").
			fontSize(FONT).fixedSize(vec2i(50, 1)).build;
		string marchSpeedContent = format("%.1f",
			m_tube.weaponParams[WeaponParamType.marchSpeed].speed);
		TextField marchSpeedField = builder(new TextField()).
			symbolFilter(&numericSymbFilter).content(marchSpeedContent).
			fontSize(FONT).build;
		marchSpeedField.onKeyReleased += (k) {
			try
			{
				float rawTgt = marchSpeedField.content[0..$-1].to!float;
				if (!isNaN(rawTgt))
				{
					float clampedTgt = max(m_tube.marchSpeedLimits.min, rawTgt);
					clampedTgt = min(m_tube.marchSpeedLimits.max, clampedTgt);
					m_tube.marchSpeed = clampedTgt;
					if (rawTgt < clampedTgt && rawTgt >= 0.0f)
						marchSpeedField.content = format("%.1f", rawTgt);
					else
						marchSpeedField.content = format("%.1f", clampedTgt);
				}
			}
			catch (Exception e) {}
		};
		marchSpeedField.onKbFocusLoss += ()
		{
			marchSpeedField.content = format("%.1f",
				m_tube.weaponParams[WeaponParamType.marchSpeed].speed);
		};

		Label activeSpeedLabel = builder(new Label()).content("ACT spd ").
			fontSize(FONT).fixedSize(vec2i(50, 1)).build;
		string activeSpeedContent = format("%.1f",
			m_tube.weaponParams[WeaponParamType.activeSpeed].speed);
		TextField activeSpeedField = builder(new TextField()).
			symbolFilter(&numericSymbFilter).content(activeSpeedContent).
			fontSize(FONT).build;
		activeSpeedField.onKeyReleased += (k) {
			try
			{
				float rawTgt = activeSpeedField.content[0..$-1].to!float;
				if (!isNaN(rawTgt))
				{
					float clampedTgt = max(m_tube.activeSpeedLimits.min, rawTgt);
					clampedTgt = min(m_tube.activeSpeedLimits.max, clampedTgt);
					m_tube.activeSpeed = clampedTgt;
					if (rawTgt < clampedTgt && rawTgt >= 0.0f)
						activeSpeedField.content = format("%.1f", rawTgt);
					else
						activeSpeedField.content = format("%.1f", clampedTgt);
				}
			}
			catch (Exception e) {}
		};
		activeSpeedField.onKbFocusLoss += ()
		{
			activeSpeedField.content = format("%.1f",
				m_tube.weaponParams[WeaponParamType.activeSpeed].speed);
		};

		Label patternLabel = builder(new Label()).content("ptrn ").
			fontSize(FONT).fixedSize(vec2i(30, 1)).build;
		Button patternButton = builder(new Button()).content(
			m_tube.weaponParams[WeaponParamType.searchPattern].searchPattern.to!string).
			fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
		patternButton.onClick += () {
			Button[] spButtons;
			foreach (WeaponSearchPattern pattern; m_tube.availableSearchPatterns)
			{
				Button btn = builder(new Button()).content(pattern.to!string).
					fontSize(FONT).build;
				btn.onClick += (WeaponSearchPattern p) {
					return {
						// we may be way too late and the weapon was changed, so we check
						if (m_tube.availableSearchPatterns.canFind(p))
						{
							m_tube.searchPattern = p;
							patternButton.content = p.to!string;
						}
					};
				} (pattern);
				spButtons ~= btn;
			}
			contextMenu(Game.guiManager, spButtons, Game.window.size,
				Game.window.mousePos, FONT + 4);
		};

		Label sensorLabel = builder(new Label()).content("sens ").
			fontSize(FONT).fixedSize(vec2i(30, 1)).build;
		Button sensorButton = builder(new Button()).content(
			m_tube.sensorMode.to!string).
			fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
		sensorButton.onClick += () {
			Button[] smButtons;
			foreach (WeaponSensorMode sensMode; m_tube.availableSensorModes)
			{
				Button btn = builder(new Button()).content(sensMode.to!string).
					fontSize(FONT).build;
				btn.onClick += (WeaponSensorMode sm) {
					return {
						// we may be way too late and the weapon was changed, so we check
						if (m_tube.availableSensorModes.canFind(sm))
						{
							m_tube.sensorMode = sm;
							sensorButton.content = sm.to!string;
						}
					};
				} (sensMode);
				smButtons ~= btn;
			}
			contextMenu(Game.guiManager, smButtons, Game.window.size,
				Game.window.mousePos, FONT + 4);
		};

		m_aimDiv = builder(vDiv([
				builder(hDiv([courseLabel, m_courseTextField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([activationRangeLabel, m_activationRangeField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([marchSpeedLabel, marchSpeedField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([activeSpeedLabel, activeSpeedField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([patternLabel, patternButton])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([sensorLabel, sensorButton])).
					fixedSize(vec2i(1, FONT + 4)).build,
				filler()
			])).borderWidth(4).fixedSize(vec2i(80, AIM_BLOCK_HEIGHT)).build;

		// bind up and down keys in cycle
		for (size_t i = 0; i < m_aimDiv.children.length - 3; i++)
		{
			TextField curField = cast(TextField)((cast(Div) m_aimDiv.children[i]).children[1]);
			assert(curField);
			TextField nextField = cast(TextField)(
				(cast(Div) m_aimDiv.children[(i + 1) % ($ - 3)]).children[1]);
			assert(nextField);
			curField.onKeyPressed += (nf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyDown)
						nf.requestKbFocus();
					};
				} (nextField);
			nextField.onKeyPressed += (cf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyUp)
						cf.requestKbFocus();
					};
				} (curField);
		}

		updateAimFieldsFromTube();
	}

	private static bool numericSymbFilter(dchar c)
	{
		if (c >= '0' && c <= '9' || c == '.' || c == '-')
			return true;
		return false;
	}

	private void createSelectWeaponContextMenu()
	{
		Button chooseEmpty = builder(new Button()).
			content("empty").fontSize(FONT).build;
		chooseEmpty.onClick += { m_tube.sendDesiredWeaponRequest(null); };
		Button[] contextButtons = [chooseEmpty];
		foreach (weaponCountPair; m_tube.room.weaponCounts.byKeyValue)
		{
			if (weaponCountPair.value > 0)
			{
				string weaponName = weaponCountPair.key;
				Button loadWeaponBtn = builder(new Button()).
					content(weaponName ~ " x" ~ weaponCountPair.value.to!string).
					fontSize(FONT).build;
				loadWeaponBtn.onClick += { m_tube.sendDesiredWeaponRequest(weaponName); };
				contextButtons ~= loadWeaponBtn;
			}
		}
		contextMenu(Game.guiManager, contextButtons, Game.window.size,
			Game.window.mousePos, FONT + 4);
	}

	private void updateWeaponContent()
	{
		string currentWeaponName = m_tube.loadedWeapon;
		if (currentWeaponName == null)
			currentWeaponName = "empty";
		if (m_tube.currentState == TubeState.unloading)
		{
			string desiredWeaponName = m_tube.desiredWeapon;
			if (desiredWeaponName == null)
				desiredWeaponName = "empty";
			m_weaponButton.content = currentWeaponName[0..4] ~ "->" ~
				desiredWeaponName[0..4];
		}
		else
			m_weaponButton.content = currentWeaponName;
		if (m_tube.currentState == TubeState.dry ||
			m_tube.currentState == TubeState.unloading ||
			m_tube.currentState == TubeState.loading)
		{
			m_weaponButton.backgroundColor = COLORS.simButtonBgnd;
			m_weaponButton.pressable = true;
		}
		else
		{
			m_weaponButton.backgroundColor = sfTransparent;
			m_weaponButton.pressable = false;
		}
		// aim-button related stuff
		if (m_tube.loadedWeapon == null)
		{
			if (m_aimButton)
				m_aimButton.pressable = false;
			if (m_aiming)
				onAimButtonClick();
			assert(!m_aiming);
		}
		else
		{
			if (m_aimButton)
				m_aimButton.pressable = true;
		}
	}

	private void updateDesiredStateButtons()
	{
		for (TubeState state = TubeState.dry; state <= TubeState.open; state++)
		{
			Button btn = m_desiredStateButtons[state];
			if (state == m_tube.desiredState)
				btn.backgroundColor = COLORS.simButtonSelectedStateBgnd;
			else
				btn.backgroundColor = COLORS.simButtonBgnd;
			// we do not allow desired state switch during loading/unloading
			if (m_tube.currentState == TubeState.unloading ||
				m_tube.currentState == TubeState.loading)
				btn.pressable = false;
			else
				btn.pressable = true;
		}
	}

	private void updateLaunchButton()
	{
		if (m_tube.loadedWeapon != null && m_tube.currentState == TubeState.open)
		{
			m_launchButton.backgroundColor = COLORS.simLaunchButtonBgnd;
			m_launchButton.fontColor = sfBlack;
			m_launchButton.pressable = true;
		}
		else
		{
			m_launchButton.backgroundColor = COLORS.simButtonDisabledBgnd;
			m_launchButton.fontColor = COLORS.simButtonDisabledFont;
			m_launchButton.pressable = false;
		}
	}
}