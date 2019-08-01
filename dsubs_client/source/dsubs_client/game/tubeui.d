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
	enum sfColor SELECTED_STATE_COLOR = sfColor(150, 15, 15, 100);
	enum sfColor INACTIVE_STATE_COLOR = CONF_COLOR;
	enum sfColor HOVER_BUTTON_COLOR_ACTIVE = sfColor(255, 150, 150, 255);
}


final class TubeUI
{
	private
	{
		Tube m_tube;
		Div m_mainDiv;
		Button[TubeState.open + 1] m_desiredStateButtons;
		Button m_launchButton;
		GuiElement m_configureButton;
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
			m_configureButton = builder(new Button()).content("Configure").
				fontSize(FONT).backgroundColor(CONF_COLOR).build;
		else
			m_configureButton = filler();
		m_launchButton = builder(new Button()).content("Launch").
			fontSize(LAUNCH_FONT).backgroundColor(LAUNCH_COLOR_DISABLED).build;
		m_desiredStateButtons[TubeState.dry] =
			builder(new Button()).content("D").
				fontSize(LAUNCH_FONT).backgroundColor(INACTIVE_STATE_COLOR).build;
		m_desiredStateButtons[TubeState.flooded] =
			builder(new Button()).content("F").
				fontSize(LAUNCH_FONT).backgroundColor(INACTIVE_STATE_COLOR).build;
		m_desiredStateButtons[TubeState.open] =
			builder(new Button()).content("O").
				fontSize(LAUNCH_FONT).backgroundColor(INACTIVE_STATE_COLOR).build;

		Div desiredStateDiv = builder(hDiv(cast(GuiElement[]) m_desiredStateButtons[])).
			fixedSize(vec2i(100, LAUNCH_FONT + 4)).borderWidth(4).build;

		m_mainDiv = builder(vDiv([
			m_tubeNameLabel,
			m_configureButton,
			m_launchButton,
			desiredStateDiv,
			m_currentStateLabel,
			m_weaponButton])).borderWidth(4).fixedSize(vec2i(80, 110)).build;

		// now we bind updates
		m_tube.onStateUpdate += &updateFromTube;
		m_launchButton.onClick += &m_tube.sendLaunchRequest;
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

	private void updateWeaponContent()
	{
		string currentWeaponName = m_tube.loadedWeapon;
		if (currentWeaponName == null)
			currentWeaponName = "empty";
		if (m_tube.currentState == TubeState.unloading ||
			m_tube.currentState == TubeState.loading)
		{
			string desiredWeaponName = m_tube.desiredWeapon;
			if (desiredWeaponName == null)
				desiredWeaponName = "empty";
			m_weaponButton.content = currentWeaponName ~ " -> " ~ desiredWeaponName;
		}
		else
			m_weaponButton.content = currentWeaponName;
		if (m_tube.currentState == TubeState.dry ||
			m_tube.currentState == TubeState.unloading ||
			m_tube.currentState == TubeState.loading)
		{
			m_weaponButton.backgroundColor = CONF_COLOR;
			m_weaponButton.pressable = true;
		}
		else
		{
			m_weaponButton.backgroundColor = sfTransparent;
			m_weaponButton.pressable = false;
		}
	}

	private void updateDesiredStateButtons()
	{
		for (TubeState state = TubeState.dry; state <= TubeState.open; state++)
		{
			Button btn = m_desiredStateButtons[state];
			if (state == m_tube.desiredState)
				btn.backgroundColor = SELECTED_STATE_COLOR;
			else
				btn.backgroundColor = INACTIVE_STATE_COLOR;
		}
	}

	private void updateLaunchButton()
	{
		if (m_tube.loadedWeapon != null && m_tube.currentState == TubeState.open)
		{
			m_launchButton.backgroundColor = LAUNCH_COLOR;
			m_launchButton.fontColor = sfBlack;
			m_launchButton.pressable = true;
		}
		else
		{
			m_launchButton.backgroundColor = LAUNCH_COLOR_DISABLED;
			m_launchButton.fontColor = sfColor(0, 0, 0, 40);
			m_launchButton.pressable = false;
		}
	}
}