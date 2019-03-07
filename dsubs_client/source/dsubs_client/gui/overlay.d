module dsubs_client.gui.overlay;

import derelict.sfml2.graphics;

import dsubs_common.containers.quadtree;

import dsubs_client.math.transform;
import dsubs_client.render.camera;
import dsubs_client.core.utils;
import dsubs_client.gui.element;
import dsubs_client.input.router;


private alias OverlayIndex = QuadTree!OverlayElement;


/// Gui element wich is not a member of binary div tree and needs general 2D indexing.
/// Overlay elements are usually tracking some point in world space while keeping
/// their screen-space size constant. Indexing is done in world space, because it is
/// more static than screen space (camera moves more often than world).
/// Index leafs must be updated when the tracked transform changes, or camera changes
/// zoom.
class OverlayElement: GuiElement
{
	private
	{
		OverlayIndex.LeafNode* m_cellNode;
		Overlay m_owner;
		Rectangle m_prevRect;
	}

	mixin Readonly!(Transform2D, "transform");

	this(Overlay owner, Transform2D trans)
	{
		m_owner = owner;
		m_transform = trans;
		// we clamp all overlay elements with overlay's viewport
		parentViewport = &parent.viewport;
		// overlays are mostly for clickable objects
		mouseTransparent = false;
	}

	/// Must be called when tracked value moves in world space. Triggers reindex.
	protected final void onTrackedUpdate(Rectangle newRect)
	{
		if (m_cellNode)
			m_cellNode.rect = newRect;
	}

	/// Called by overlay when new coordinates of all tracked objects and camera
	/// state are ready to be applied to the element.
	protected void onPreDraw(ref const(mat3x3d) world2screen,
		ref const(mat3x3d) screen2world)
	{
		// first we need to update the position.
		vec2d newPos = world2screen * transform.wposition;
	}
}


/// Overlay container that indexes OverlayElements and dispatches
/// standard input events to them.
class Overlay: GuiElement
{
	private
	{
		OverlayIndex m_index;
	}

	this() {}
}