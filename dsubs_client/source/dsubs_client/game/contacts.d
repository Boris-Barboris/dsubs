module dsubs_client.game.contacts;

import std.traits: EnumMembers;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.game.cic.messages;
import dsubs_client.game.sonardisp: SonarDisplay;
import dsubs_client.game.waterfall: Waterfall;
import dsubs_client.game.tacoverlay;
import dsubs_client.game;


/// Client representation of ContactData object
struct ClientContactData
{
	this(ContactData data)
	{
		m_data = data;
	}

	private ContactData m_data;
	@property const(ContactData) cdata() const { return m_data; }
	alias cdata this;
}


/// Client representation of a contact object
final class ClientContact
{
	this(Contact ctc, int hydrophoneCount)
	{
		m_ctc = ctc;
		m_tactDispEl = new TacticalContactElement(Game.simState.tacticalOverlay, this);
		m_trackerEls.length = hydrophoneCount;
	}

	private SonarDispContactDataElement m_sonarDispEl;
	private TacticalContactElement m_tactDispEl;
	private HydrophoneTrackerElement[] m_trackerEls;

	mixin Readonly!(ClientContactData*, "lastRay");

	/// collection of all data of this contact
	private ClientContactData*[int] m_dataHash;
	/// get ContactData iterator
	auto contactDataRange() { return m_dataHash.byValue; }

	HydrophoneTrackerElement[] trackerElements() { return m_trackerEls; }

	Contact m_ctc;
	alias m_ctc this;

	void drop()
	{
		m_tactDispEl.drop();
		if (m_sonarDispEl)
		{
			m_sonarDispEl.drop();
			m_sonarDispEl = null;
		}
		foreach (hte; m_trackerEls)
		{
			if (hte !is null)
				hte.drop();
		}
		m_dataHash.clear();
	}

	void addData(ClientContactData* cdata)
	{
		m_dataHash[cdata.id] = cdata;
		if (cdata.type == DataType.Ray)
		{
			if (m_lastRay is null)
				m_lastRay = cdata;
			else if (m_lastRay.time <= cdata.time)
				m_lastRay = cdata;
		}
		switch (cdata.source.type)
		{
			case DataSourceType.ActiveSonar:
				if (m_sonarDispEl !is null)
				{
					if (m_sonarDispEl.data.time < cdata.time)
					{
						// old m_sonarDispEl must go
						m_sonarDispEl.drop();
						m_sonarDispEl = new SonarDispContactDataElement(
							Game.simState.gui.sonardisp.overlay, cdata, this);
					}
				}
				else
				{
					m_sonarDispEl = new SonarDispContactDataElement(
						Game.simState.gui.sonardisp.overlay, cdata, this);
				}
				break;
			default:
				break;
		}
		m_tactDispEl.addData(cdata);
	}

	void updateContact(MsgT)(MsgT msg)
		if (isContactUpdateMsg!MsgT)
	{
		static if (is(MsgT == CICContactUpdateTypeReq))
			m_ctc.type = msg.type;
		else static if (is(MsgT == CICContactUpdateSolutionReq))
			m_ctc.solution = msg.solution;
		else static if (is(MsgT == CICContactUpdateDescriptionReq))
			m_ctc.description = msg.description;
		else static if (is(MsgT == CICContactUpdateReq))
		{
			m_ctc.type = msg.type;
			m_ctc.solution = msg.solution;
			m_ctc.description = msg.description;
		}
		m_tactDispEl.updateFromContact();
		if (m_sonarDispEl)
			m_sonarDispEl.updateFromContact(this);
	}

	void updateData(ClientContactData* cdata)
	{
		if (m_sonarDispEl && m_sonarDispEl.data is cdata)
			m_sonarDispEl.updateFromData();
	}

	void updateTracker(HydrophoneTracker ht)
	{
		if (m_trackerEls[ht.id.sensorIdx] is null)
		{
			// new tracker
			Waterfall.TrackerOverlay wto = Game.simState.gui.
				waterfalls[ht.id.sensorIdx].trackerOverlay;
			m_trackerEls[ht.id.sensorIdx] = new HydrophoneTrackerElement(wto, ht);
		}
		else
		{
			// update old one
			m_trackerEls[ht.id.sensorIdx].updateFromTracker(ht);
		}
	}

	void dropTracker(int hydrophoneIdx)
	{
		if (m_trackerEls[hydrophoneIdx])
			m_trackerEls[hydrophoneIdx].drop();
		m_trackerEls[hydrophoneIdx] = null;
	}

	void removeData(int dataId)
	{
		m_dataHash.remove(dataId);
		if (m_sonarDispEl && m_sonarDispEl.data.id == dataId)
		{
			m_sonarDispEl.drop();
			m_sonarDispEl = null;
		}
		m_tactDispEl.removeData(dataId);
	}
}


/// Contacts and their data that the client knows about. May be out of sync with CIC server.
final class ClientContactManager
{
	private int m_hydrophoneCount;

	this(CICReconnectStateRes msg, int hydrophoneCount)
	{
		m_hydrophoneCount = hydrophoneCount;
		foreach (Contact ctc; msg.contacts)
			m_contactHash[ctc.id] = new ClientContact(ctc, hydrophoneCount);
	}

	/// collection of all data of this contact
	private ClientContact[ContactId] m_contactHash;
	/// collection of all contact data
	private ClientContactData*[int] m_dataHash;

	ClientContact get(ContactId id) { return m_contactHash[id]; }

	void handleContactCreated(CICContactCreatedFromDataRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null, "contact already exists");
		m_contactHash[msg.newContact.id] = new ClientContact(msg.newContact, m_hydrophoneCount);
		handleContactData(msg.initialData);
	}

	void handleContactCreated(CICContactCreatedFromHTrackerRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null, "contact already exists");
		m_contactHash[msg.newContact.id] = new ClientContact(msg.newContact, m_hydrophoneCount);
		handleTracker(msg.tracker);
	}

	void handleTracker(HydrophoneTracker tracker)
	{
		ContactId cid = tracker.id.ctcId;
		ClientContact cc = m_contactHash[cid];
		cc.updateTracker(tracker);
	}

	void handleContactData(ContactData newData)
	{
		ClientContact* ctc = newData.ctcId in m_contactHash;
		enforce(ctc !is null, "contact does not exist");
		ClientContactData** existing = newData.id in m_dataHash;
		if (existing !is null)
		{
			if (ctc.id != (*existing).ctcId)
			{
				// data changed owner
				m_contactHash[(*existing).ctcId].removeData((*existing).id);
				(*existing).m_data = newData;
				ctc.addData(*existing);
			}
			else
			{
				(*existing).m_data = newData;
				ctc.updateData(*existing);
			}
			return;
		}
		ClientContactData* cdata = new ClientContactData(newData);
		m_dataHash[cdata.id] = cdata;
		ctc.addData(cdata);
	}

	void handleTrimContactData(ContactId ctcId, usecs_t olderThan)
	{
		ClientContact* ctc = ctcId in m_contactHash;
		enforce(ctc !is null, "contact does not exist");
		ClientContactData*[] contactData = ctc.m_dataHash.values;
		foreach (ClientContactData* ccd; contactData)
		{
			if (ccd.time < olderThan)
			{
				ctc.removeData(ccd.id);
				m_dataHash.remove(ccd.id);
			}
		}
	}

	void handleContactUpdate(MsgT)(MsgT msg)
		if (isContactUpdateMsg!MsgT)
	{
		m_contactHash[msg.id].updateContact(msg);
	}

	void handleDropContact(ContactId id)
	{
		foreach (ClientContactData* ctd; m_contactHash[id].contactDataRange)
			m_dataHash.remove(ctd.id);
		m_contactHash[id].drop();
		m_contactHash.remove(id);
	}

	void handleDropData(int dataId)
	{
		if (dataId !in m_dataHash)
			return;
		ContactId ctcId = m_dataHash[dataId].ctcId;
		m_contactHash[ctcId].removeData(dataId);
		m_dataHash.remove(dataId);
	}

	void handleDropTracker(TrackerId tid)
	{
		ContactId cid = tid.ctcId;
		ClientContact cc = m_contactHash.get(cid, null);
		if (cc)
			cc.dropTracker(tid.sensorIdx);
	}

	void hadleMergeContact(ContactId srcId, ContactId destId)
	{
		assert(srcId != destId);
		ClientContact cs = m_contactHash[srcId];
		ClientContact cd = m_contactHash[destId];
		foreach (ClientContactData* ctd; cs.contactDataRange)
		{
			ctd.m_data.ctcId = destId;
			cd.addData(ctd);
		}
		cs.drop();
		m_contactHash.remove(srcId);
	}
}


/// Generate buttons, that contain common actions to perform on contact
Button[] commonContactContextMenu(ClientContact ctc)
{
	Button[] res;
	Button btn;
	// classification
	Button[] classifications;
	foreach (ctype; EnumMembers!ContactType)
	{
		btn = builder(new Button()).fontSize(15).content(ctype.to!string).build();
		btn.onClick += {
			Contact curContact = ctc.m_ctc;
			if (curContact.type != ctype)
			{
				Game.ciccon.sendMessage(
					immutable CICContactUpdateTypeReq(curContact.id, ctype));
			}
		};
		classifications ~= btn;
	}
	NestedContextBtn classifySubmenu = builder(new NestedContextBtn(classifications, 20)).
		fontSize(15).content("classify as").build();
	res ~= classifySubmenu;
	// description
	Button describebtn = builder(new Button()).fontSize(15).content(
		"describe").build();
	describebtn.onClick += {
		// we need to create new panel in the center of the screen
		// that allows to enter new contact description.
		Contact curContact = ctc.m_ctc;
		TextField descriptionTextField = builder(new TextField()).
			content(curContact.description).fontSize(25).fixedSize(vec2i(400, 30)).build;
		auto layout = vDiv([filler(),
			builder(hDiv([filler(), descriptionTextField, filler()])).fixedSize(vec2i(0, 30)).build,
			filler()]);
		Panel editPanel = new Panel(layout);
		Game.guiManager.addPanel(editPanel);
		descriptionTextField.onKbFocusLoss += ()
		{
			Game.guiManager.removePanel(editPanel);
		};
		descriptionTextField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyEscape)
				descriptionTextField.returnKbFocus();
			if (evt.code == sfKeyReturn)
			{
				// send description update
				string clampedDesc = descriptionTextField.content.str;
				if (clampedDesc.length > 128)
					clampedDesc.length = 128;
				CICContactUpdateDescriptionReq msg = CICContactUpdateDescriptionReq(
					curContact.id, clampedDesc);
				Game.ciccon.sendMessage(cast(immutable) msg);
			}
		};
		descriptionTextField.requestKbFocus();
		descriptionTextField.selectAll();
	};
	res ~= describebtn;
	// trimming
	Button[] trimmingBtns;
	foreach (int secsToLeave; [30, 60, 180, 300])
	{
		btn = builder(new TrimBtn(ctc.id, secsToLeave)).fontSize(15).
			content(secsToLeave.to!string ~ "s").build();
		trimmingBtns ~= btn;
	}
	NestedContextBtn trimSubmenu = builder(new NestedContextBtn(trimmingBtns, 20)).
		fontSize(15).content("trim to last").build();
	res ~= trimSubmenu;
	// drop
	btn = builder(new Button()).fontSize(15).content("drop contact").build();
	btn.onClick += {
		Game.ciccon.sendMessage(immutable CICDropContactReq(ctc.id));
	};
	res ~= btn;
	return res;
}

// workaround to D lambda capturing rules. Another solution:
// https://forum.dlang.org/post/imtygxgjovnvrrfmxpok@forum.dlang.org
private final class TrimBtn: Button
{
	private
	{
		ContactId m_ctcId;
		int m_secsToLeave;
	}

	this(ContactId ctcId, int secsToLeave)
	{
		super(ButtonType.SYNC);
		m_ctcId = ctcId;
		m_secsToLeave = secsToLeave;
		onClick += &processClick;
	}

	private void processClick()
	{
		auto msg = immutable CICTrimContactData(
			m_ctcId, Game.simState.lastServerTime - m_secsToLeave * 1000_000);
		Game.ciccon.sendMessage(msg);
	}
}