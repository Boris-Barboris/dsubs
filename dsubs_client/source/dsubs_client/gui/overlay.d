module dsubs_client.gui.overlay;

import derelict.sfml2.graphics;

// import dsubs_common.containers.quadtree;

import dsubs_client.math.transform;
import dsubs_client.render.camera;
import dsubs_client.core.utils;
import dsubs_client.gui.element;
import dsubs_client.input.router;


// private alias OverlayIndex = QuadTree!OverlayElement;

/// Overlay elements are usually tracking some point in world space while keeping
/// their screen-space size constant.
class OverlayElement: GuiElement
{
	mixin Readonly!(Overlay, "owner");

	/// Overlay elements may require hiding, or only small subset of them to be drawn
	private bool m_hidden = false;

	mixin FinalGetSet!(bool, "hidden", "if (rhs) onHide();");

	this(Overlay owner)
	{
		m_owner = owner;
		// we clamp all overlay elements with overlay's viewport
		parentViewport = &owner.viewport();
		// overlays are mostly for clickable objects
		mouseTransparent = false;
		owner.m_elements[this] = true;
	}

	/// transforms center in screen-space to rounded left upper angle to set position to
	final vec2i center2lu(vec2d centerOnScreen)
	{
		return cast(vec2i) centerOnScreen - size / 2;
	}

	// We do not apply in-rect scissor test to overlay elements
	override void updateViewport()
	{
		m_viewport = *parentViewport;
	}

	/// Overlay elements must ignore mouse scroll in order to not block zooming
	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseWheelScrolled)
			return null;
		return super.getFromPoint(evt, x, y);
	}

	/// Called by overlay when new coordinates of all tracked objects and camera
	/// state are ready to be applied to the element,
	/// right before actually drawing the element.
	protected abstract void onPreDraw();
}


/// Overlay container that indexes OverlayElements and dispatches
/// standard input events to them.
class Overlay: GuiElement
{
	private bool[OverlayElement] m_elements;

	/// remove child overlay element
	void remove(OverlayElement el)
	{
		m_elements.remove(el);
		if (!el.hidden)
			el.onHide();
	}

	override void onHide()
	{
		super.onHide();
		foreach (OverlayElement el; m_elements.byKey)
		{
			if (!el.hidden)
				el.onHide();
		}
	}

	/// must return coordinates, transformed from world space to window space.
	abstract vec2d world2windowPos(vec2d world);
	/// must return rotation, transformed from world space to window space.
	abstract double world2windowRot(double world);

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		foreach (OverlayElement el; m_elements.byKey)
		{
			if (!el.hidden)
			{
				el.onPreDraw();
				el.draw(wnd, usecsDelta);
			}
		}
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (rectContainsPoint(x, y))
		{
			// now let's find the element to route event to
			foreach (OverlayElement el; m_elements.byKey)
			{
				if (!el.hidden)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			return this;
		}
		return null;
	}
}