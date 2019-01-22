module dsubs_client.game.cameracontroller;

import std.math;

import std.experimental.logger;

import dsubs_common.math;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.render.worldmanager;
import dsubs_client.render.camera;



/// Camera controller that handles panning and zooming
final class CameraController: WorldMouseReceiver
{
	float zoomTgtK = 0.25f;
	float kbPanSpeed = 1500.0f;
	float kbZoomSpeed = 4.0f;

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
			&resetCameraToPlayerSub);
		Game.render.onPreRender += &handleSmooth;
	}

	private void resetCameraToPlayerSub()
	{
		Game.worldManager.camCtx.camera.center =
					Game.simState.playerSub.transform.wposition;
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
		bool smoothing = false;
		double targetZoom;
		vec2d zoomPivot;
		double zoomVel = 0.0;
		double zoomAcc = 90.0;
	}

	private static double parabolicMove(double y1, double v1, double y2,
		double k, double dt, out double v3)
	{
		assert(k > 0.0);
		assert(dt > 0.0);
		double d = fabs(y2 - y1);
		double sign = sgn(y2 - y1);
		if (v1 * sign < 0.0)
			v1 = 0.0;
		v1 = fabs(v1);
		double t1 = v1 / 2 / k;
		assert(t1 >= 0.0);
		double cc = d - k * t1 * t1;
		if (cc <= 1e-10)
		{
			// descent on second parabola
			double tleft = t1 - dt;
			if (tleft <= 0.0)
			{
				v3 = 0.0;
				return y2;
			}
			v3 = sign * tleft * k * 2;
			return y2 - sign * k * tleft * tleft;
		}
		else
		{
			// ascent on first parabola
			double t2sqr = 2 * (d + k * t1 * t1) / k;
			double t2 = sqrt(t2sqr);
			if (t1 + dt >= t2)
			{
				v3 = 0.0;
				return y2;
			}
			double tres = t1 + dt;
			if (tres <= t2 / 2)
			{
				v3 = sign * 2 * k * tres;
				double y0 = y1 - sign * k * t1 * t1;
				return y0 + sign * k * tres * tres;
			}
			else
			{
				double tleft = t2 - tres;
				v3 = sign * 2 * k * tleft;
				return y2 - sign * k * tleft * tleft;
			}
		}
	}

	private void handleSmooth(long usecs)
	{
		if (!smoothing)
			return;
		double dt = double(usecs) / 1e6;
		Camera2D camera = Game.worldManager.camCtx.camera;
		// zooming
		double oldZoom = camera.zoom;
		double accK = targetZoom < oldZoom ? 1.6 : 1.0;
		camera.zoom = parabolicMove(oldZoom, zoomVel, targetZoom, accK * zoomAcc * oldZoom, dt, zoomVel);
		if (camera.zoom == targetZoom)
			smoothing = false;
		// panning while zooming
		vec2d topan = zoomPivot / oldZoom - zoomPivot / camera.zoom;
		if (zoomVel < 0)
			topan = 0.4 * topan;
		camera.pan(topan);
	}

	HandleResult handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, float delta)
	{
		Camera2D camera = Game.worldManager.camCtx.camera;
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
				if (isNaN(targetZoom))
					targetZoom = camera.zoom;
				double oldZoom = targetZoom;
				double dzoom = oldZoom * zoomTgtK * delta;
				targetZoom = fmin(25.0, fmax(0.001, targetZoom + dzoom));
				// point under cursor does not move on the screen during zoom
				double ux = x - wnd.width / 2.0;
				double uy = y - wnd.height / 2.0;
				zoomPivot = vec2d(ux, -uy);
				smoothing = true;
				break;
			}
			default:
				break;
		}
		return HandleResult(false);
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