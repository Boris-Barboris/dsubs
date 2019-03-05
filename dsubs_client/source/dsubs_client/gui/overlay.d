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
	}

	mixin Readonly!(Transform2D, "transform");

	this(Overlay owner, Transform2D trans)
	{
		m_owner = owner;
		m_transform = trans;
		// we clamp all overlay elements with overlay's viewport
		parent = owner;
		parentViewport = &parent.viewport;
		// overlays are mostly for clickable objects
		mouseTransparent = false;
	}

	/// This method must contain the logic to update element position
	/// when the tracked object moves in world-space.
	protected void onTrackedUpdate()
	{

	}

	/// when position or size of the
	private void updateInIndex()
	{

	}

	override void draw(Window wnd, long usecsDelta)
	{

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