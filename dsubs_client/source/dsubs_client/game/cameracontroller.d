module dsubs_client.game.cameracontroller;

import std.math;

import std.experimental.logger;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.router;
import dsubs_client.render.worldmanager;



/// Camera controller that handles panning and zooming
final class CameraController: WorldMouseReceiver
{
	float zoomSpeed = 0.25f;

	bool isMouseEventInteresting(Window wnd, const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseButtonPressed && evt.mouseButton.button == sfMouseRight)
			return true;
		if (evt.type == sfEvtMouseWheelMoved)
			return true;
		return false;
	}

	private
	{
		int prevX, prevY;
	}

	void handleMousePos(Window wnd, const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
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
			case sfEvtMouseWheelMoved:
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
	HandleResult handleKeyboard(Window wnd, const sfEvent* evt) { return HandleResult(true); }
}