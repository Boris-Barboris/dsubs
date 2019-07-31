module dsubs_client.game.tubeui;

import std.algorithm: map;
import std.algorithm.comparison: min, max;

import core.time: MonoTime;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;
import dsubs_client.game;
import dsubs_client.game.overlay;



private
{
	enum int FONT = 12;
	enum int LAUNCH_FONT = 15;
	enum sfColor CONF_COLOR = sfColor(15, 15, 15, 120);
	enum sfColor LAUNCH_COLOR = sfColor(255, 15, 15, 200);
	enum sfColor LAUNCH_COLOR_DISABLED = sfColor(255, 15, 15, 20);
	enum sfColor DRY_COLOR = sfColor(15, 255, 15, 200);
	enum sfColor FLOOD_COLOR = sfColor(255, 255, 15, 200);
	enum sfColor OPEN_COLOR = sfColor(255, 15, 15, 200);
}


final class TubeUI
{
	private
	{
		Tube m_tube;
		Div m_mainDiv;
		Button[TubeState.open + 1] m_desiredStateButtons;
		Button m_launchButton;
		Button m_configureButton;
		Label m_currentStateLabel;
		Label m_weaponLabel;
		Label m_tubeNameLabel;
		TubeState m_activeDesiredState;
	}

	@property Div mainDiv() { return m_mainDiv; }

	this(Tube tube)
	{
		m_tube = tube;

		m_tubeNameLabel = builder(new Label()).content("tube " ~ (m_tube.id + 1).to!string).
			fontSize(FONT).build;
		m_weaponLabel = builder(new Label()).fontSize(FONT).build;
		m_currentStateLabel = builder(new Label()).fontSize(FONT).build;
		m_configureButton = builder(new Button()).content("Configure").
			fontSize(FONT).backgroundColor(CONF_COLOR).build;
		m_launchButton = builder(new Button()).content("Launch").
			fontSize(LAUNCH_FONT).backgroundColor(LAUNCH_COLOR_DISABLED).build;
		m_desiredStateButtons[TubeState.dry] =
			builder(new Button(ButtonType.TOGGLE)).content("D").
				fontSize(LAUNCH_FONT).backgroundColor(DRY_COLOR).build;
		m_desiredStateButtons[TubeState.flooded] =
			builder(new Button(ButtonType.TOGGLE)).content("F").
				fontSize(LAUNCH_FONT).backgroundColor(FLOOD_COLOR).build;
		m_desiredStateButtons[TubeState.open] =
			builder(new Button(ButtonType.TOGGLE)).content("O").
				fontSize(LAUNCH_FONT).backgroundColor(OPEN_COLOR).build;

		foreach (Button btn; m_desiredStateButtons[])
		{
			btn.fontColor = sfBlack;
			btn.onClick += (b) {
				return
					{
						b.fontColor =
						b.state == ButtonState.ACTIVE ? sfCyan : sfBlack;
					};
				} (btn);
		}
		m_desiredStateButtons[TubeState.dry].simulateClick();

		Div desiredStateDiv = builder(hDiv(cast(GuiElement[]) m_desiredStateButtons[])).
			fixedSize(vec2i(100, LAUNCH_FONT + 4)).borderWidth(4).build;

		m_mainDiv = builder(vDiv([
			m_tubeNameLabel,
			m_configureButton,
			m_launchButton,
			desiredStateDiv,
			m_currentStateLabel,
			m_weaponLabel])).borderWidth(4).fixedSize(vec2i(100, 120)).build;

		// now we bind updates
		m_tube.onStateUpdate += &updateFromTube;
	}

	void updateFromTube(Tube t)
	{
		trace("updateFromTube called");
		assert(t is m_tube);
		updateWeaponContent();
		// update state label
		m_currentStateLabel.content = m_tube.currentState.to!string;
		updateDesiredStateButtons();
		updateLaunchButton();
	}

	private void updateWeaponContent()
	{
		string currentWeaponName = m_tube.loadedWeapon;
		if (currentWeaponName == null)
			currentWeaponName = "empty";
		trace(currentWeaponName);
		if (m_tube.currentState == TubeState.unloading ||
			m_tube.currentState == TubeState.loading)
		{
			string desiredWeaponName = m_tube.desiredWeapon;
			if (desiredWeaponName == null)
				desiredWeaponName = "empty";
			trace(desiredWeaponName);
			m_weaponLabel.content = currentWeaponName ~ " -> " ~ desiredWeaponName;
		}
		else
			m_weaponLabel.content = currentWeaponName;
	}

	private void updateDesiredStateButtons()
	{
		if (m_tube.desiredState != m_activeDesiredState)
		{
			m_activeDesiredState = m_tube.desiredState;
			Button newActiveBtn = m_desiredStateButtons[m_tube.desiredState];
			assert(newActiveBtn.state == ButtonState.INACTIVE);
			newActiveBtn.state = ButtonState.ACTIVE;
			foreach (Button b; m_desiredStateButtons[])
				if (b !is newActiveBtn)
					b.state = ButtonState.INACTIVE;
		}
	}

	private void updateLaunchButton()
	{
		if (m_tube.loadedWeapon != null && m_tube.currentState == TubeState.open)
		{
			m_launchButton.backgroundColor = LAUNCH_COLOR;
			m_launchButton.fontColor = sfBlack;
		}
		else
		{
			m_launchButton.backgroundColor = LAUNCH_COLOR_DISABLED;
			m_launchButton.fontColor = sfColor(0, 0, 0, 40);
		}
	}
}