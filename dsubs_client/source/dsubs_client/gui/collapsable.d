module dsubs_client.gui.collapsable;

import derelict.sfml2.graphics;

import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.gui.element;
import dsubs_client.gui.button;
import dsubs_client.gui.label;
import dsubs_client.gui.div;
import dsubs_client.render.shapes;


/// Collapsable vertical div container for another element
final class Collapsable: Div
{
	private
	{
		GuiElement m_child, m_childFiller;
		Div m_headerDiv;
		CircleShape m_titleTriangle;
		Button m_titleShapeButton;
		Label m_title;
		bool m_collapsed = true;
	}

	@property bool collapsed() const { return m_collapsed; }

	@property Label title() { return m_title; }

	@property GuiElement child() { return m_child; }

	this(GuiElement child, string title)
	{
		m_titleTriangle = new CircleShape(5.0f, 3);
		m_titleTriangle.fillColor = sfWhite;
		m_title = new Label();
		m_title.mouseTransparent = false;
		m_titleShapeButton = new Button();
		m_titleShapeButton.fixedSize(vec2i(16, 10));
		m_title.content = title;
		m_childFiller = filler(0);
		m_headerDiv = hDiv(cast(GuiElement[]) [m_titleShapeButton, m_title]);
		m_headerDiv.layoutType = layoutType.FIXED;
		m_headerDiv.size = vec2i(16, 16);
		super(DivType.VERT, [m_headerDiv, m_childFiller]);
		mouseTransparent = false;
		// layoutType = layoutType.FIXED;
		m_child = child;
		m_titleTriangle.rotation = 180.0f;
		m_titleShapeButton.onClick += &toggleCollapsed;
	}

	void toggleCollapsed()
	{
		if (m_collapsed)
		{
			setChild(m_child, 1);
			size = vec2i(size.x, m_headerDiv.size.y + m_child.size.y);
			m_titleTriangle.rotation = 0.0f;
		}
		else
		{
			setChild(m_childFiller, 1);
			size = vec2i(size.x, m_headerDiv.size.y);
			m_titleTriangle.rotation = 180.0f;
		}
		m_collapsed = !m_collapsed;
	}

	override void onBeforeChildrenDraw(Window wnd, long usecsDelta)
	{
		// draw shape on top of toggle button in a header
		m_titleTriangle.center = m_titleShapeButton.center;
		m_titleTriangle.render(wnd);
	}
}