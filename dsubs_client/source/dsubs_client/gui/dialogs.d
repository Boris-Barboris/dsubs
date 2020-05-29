module dsubs_client.gui.dialogs;

import derelict.sfml2.window;

import dsubs_client.common;

import dsubs_client.colorscheme;
import dsubs_client.game;
import dsubs_client.gui;


void startYesNoDialog(string question, void delegate() onYes,
	void delegate() onNo, int width = 400)
{
	assert(onYes !is null);
	Label questionLabel = builder(new Label()).content(question).
		fontSize(25).htextAlign(HTextAlign.CENTER).build;
	Button yesBtn = builder(new Button()).content("YES").
		htextAlign(HTextAlign.CENTER).fontSize(25).build;
	Button noBtn = builder(new Button()).content("NO").
		htextAlign(HTextAlign.CENTER).fontSize(25).build;
	auto layout = vDiv([
		filler(),
		builder(hDiv([filler(),
			builder(vDiv([
				questionLabel,
				builder(hDiv([yesBtn, noBtn])).fixedSize(vec2i(width, 30)).build
			])).fixedSize(vec2i(width, 60)).backgroundColor(COLORS.simPanelBgnd).build,
			filler()])).fixedSize(vec2i(1, 60)).build,
		filler()]);
	Panel dialogPanel = new Panel(layout);
	Game.guiManager.addPanel(dialogPanel);

	yesBtn.onClick += {
		// callback before returnKbFocus because returnKbFocus will
		// call removePanel and removePanel calls onHide that calls returnKbFocus.
		onYes();
		Game.guiManager.removePanel(dialogPanel);
	};
	noBtn.onClick += {
		onNo();
		Game.guiManager.removePanel(dialogPanel);
	};
}