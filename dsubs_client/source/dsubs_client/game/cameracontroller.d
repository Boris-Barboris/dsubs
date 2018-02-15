module dsubs_client.game.cameracontroller;

import std.functional;
import std.math;

import std.experimental.logger;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.simulation;
import dsubs_client.gui;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.render.worldmanager;



/// Camera controller that handles panning and zooming
final class CameraController: WorldMouseReceiver
{
	float zoomSpeed = 0.25f;
	float kbPanSpeed = 2000.0f;
	float kbZoomSpeed = 5.0f;

	bool isMouseEventInteresting(Window wnd, const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseButtonPressed && evt.mouseButton.button == sfMouseRight)
			return true;
		if (evt.type == sfEvtMouseWheelScrolled)
			return true;
		return false;
	}

	/// register panning and zooming hotkeys
	this()
	{
		Game.hotkeyManager.addHoldkey(&handleKeyboard);
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyEscape),
			toDelegate(&resetCameraToPlayerSub));
	}

	private static void resetCameraToPlayerSub()
	{
		Game.worldManager.camCtx.camera.center =
					Game.simState.playerSub.transform.position;
	}

	private void handleKeyboard(long usecs, Modifier curMods)
	{
		if (curMods == Modifier.NONE)
		{
			auto camera = Game.worldManager.camCtx.camera;

			// pan
			vec2d pan = vec2d(0.0, 0.0);
			if (sfKeyboard_isKeyPressed(sfKeyLeft))
				pan.x -= 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyRight))
				pan.x += 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyDown))
				pan.y -= 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyUp))
				pan.y += 1.0;
			pan *= double(usecs) / 1e6 * kbPanSpeed;
			camera.pan(pan / camera.zoom);

			// zoom
			double dz = 0.0;
			if (sfKeyboard_isKeyPressed(sfKeyE))
				dz += 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyQ))
				dz -= 1.0;
			dz *= double(usecs) / 1e6 * kbZoomSpeed;
			dz = fmax(-0.5, dz);
			camera.zoom = fmin(25.0, fmax(0.001, camera.zoom * (1.0 + dz)));
		}
	}

	private
	{
		int prevX, prevY;
	}

	void handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, float delta)
	{
		auto camera = Game.worldManager.camCtx.camera;
		switch (evt.type)
		{
			case sfEvtMouseButtonPressed:
				if (evt.mouseButton.button == sfMouseRight)
				{
					InputRouter.mouseFocused = this;	// we capture the mouse
					prevX = x;
					prevY = y;
				}
				break;
			case sfEvtMouseButtonReleased:
				if (evt.mouseButton.button == sfMouseRight)
					InputRouter.mouseFocused = null;	// release the mouse
				break;
			case sfEvtMouseMoved:
			{
				vec2d panning = vec2d(prevX - x, y - prevY) / camera.zoom;
				prevX = x;
				prevY = y;
				camera.pan(panning);
				break;
			}
			case sfEvtMouseWheelScrolled:
			{
				double oldZoom = camera.zoom;
				double dzoom = camera.zoom * zoomSpeed * delta;
				camera.zoom = fmin(25.0, fmax(0.001, camera.zoom + dzoom));
				// point under cursor does not move on the screen during zoom
				double ux = x - wnd.width / 2.0;
				double uy = y - wnd.height / 2.0;
				vec2d uc = vec2d(ux, -uy);
				vec2d topan = uc / oldZoom - uc / camera.zoom;
				if (delta < 0)
					topan = 0.5 * topan;
				camera.pan(topan);
				break;
			}
			default:
				break;
		}
	}

	// dummy handlers just to conform to IInputReciever
	void handleMouseEnter() {}
	void handleMouseLeave() {}
	void handleMouseFocusGain() {}
	void handleMouseFocusLoss() {}
	void handleKbFocusGain() {}
	void handleKbFocusLoss() {}
	HandleResult handleKeyboard(Window wnd, const sfEvent* evt)
	{
		return HandleResult(true);
	}
}