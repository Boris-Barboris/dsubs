module dsubs_client.game.wireui;

import std.algorithm: map, canFind;
import std.algorithm.comparison: min, max;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game;
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;


private
{
	enum int FONT = 14;
	enum int LABEL_WIDTH = 100;
}


final class WireUi
{
	private
	{
		Slider m_slider;
		Label m_label;
		Div m_div;
		int m_wireId;
		float m_maxLength;
	}

	this(int wireId, string wireName, float maxLength)
	{
		m_wireId = wireId;
		m_maxLength = maxLength;
		m_label = builder(new Label()).content(wireName).
			fontSize(FONT).fixedSize(vec2i(LABEL_WIDTH, 1)).build;
		m_slider = new Slider();
		m_slider.value = 0.0f;
		m_slider.onDragEnd += (float newValue) {
			Game.ciccon.sendMessage(cast(immutable) CICWireDesiredLengthReq(
				m_wireId, newValue * m_maxLength));
		};
		m_div = hDiv([m_label, m_slider]);
		m_div.fixedSize = vec2i(1, FONT + 8);
	}

	void updateDesiredLength(float desired)
	{
		m_slider.value = desired / m_maxLength;
	}

	@property Div rootDiv() { return m_div; }
}