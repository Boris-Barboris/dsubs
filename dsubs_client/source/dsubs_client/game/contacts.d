module dsubs_client.game.contacts;

import std.traits: EnumMembers;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.game.cic.messages;
import dsubs_client.game.sonardisp: SonarDisplay;
import dsubs_client.game.waterfall: Waterfall;
import dsubs_client.game.overlay;
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
	this(Contact ctc)
	{
		m_ctc = ctc;
		m_tactDispEl = new TacticalContactElement(Game.simState.tacticalOverlay, this);
	}

	private SonarDispContactDataElement m_sonarDispEl;
	private TacticalContactElement m_tactDispEl;

	/// collection of all data of this contact
	private ClientContactData*[int] m_dataHash;
	/// get ContactData iterator
	auto contactDataRange() { return m_dataHash.byValue; }

	private Contact m_ctc;
	@property const(Contact) ctc() const { return m_ctc; }
	alias ctc this;

	void drop()
	{
		m_tactDispEl.drop();
		if (m_sonarDispEl)
		{
			m_sonarDispEl.drop();
			m_sonarDispEl = null;
		}
		m_dataHash.clear();
	}

	void addData(ClientContactData* cdata)
	{
		m_dataHash[cdata.id] = cdata;
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

	void updateContact(Contact ctc)
	{
		m_ctc = ctc;
		m_tactDispEl.updateFromContact();
		if (m_sonarDispEl)
			m_sonarDispEl.updateFromContact(this);
	}

	void updateData(ClientContactData* cdata)
	{
		if (m_sonarDispEl && m_sonarDispEl.data is cdata)
			m_sonarDispEl.updateFromData();
	}

	void removeData(int dataId)
	{
		m_dataHash.remove(dataId);
		if (m_sonarDispEl && m_sonarDispEl.data.id == dataId)
			m_sonarDispEl.drop();
		m_tactDispEl.removeData(dataId);
		m_sonarDispEl = null;
	}
}


/// Contacts and their data that the client knows about. May be out of sync with CIC server.
final class ClientContactManager
{
	this(CICReconnectStateRes msg)
	{
		foreach (Contact ctc; msg.contacts)
			m_contactHash[ctc.id] = new ClientContact(ctc);
	}

	/// collection of all data of this contact
	private ClientContact[ContactId] m_contactHash;
	/// collection of all contact data
	private ClientContactData*[int] m_dataHash;

	ClientContact get(ContactId id) { return m_contactHash[id]; }

	void handleContactCreatedRes(CICContactCreatedRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null, "contact already exists");
		m_contactHash[msg.newContact.id] = new ClientContact(msg.newContact);
		handleContactData(msg.initialData);
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

	void handleContactUpdate(Contact msg)
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
		ContactId ctcId = m_dataHash[dataId].ctcId;
		m_contactHash[ctcId].removeData(dataId);
		m_dataHash.remove(dataId);
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
	Button btn = builder(new Button()).fontSize(15).content("drop contact").build();
	btn.onClick += {
		Game.ciccon.sendMessage(immutable CICDropContactReq(ctc.id));
	};
	res ~= btn;
	Button[] classifications;
	foreach (ctype; EnumMembers!ContactType)
	{
		btn = builder(new Button()).fontSize(15).content(ctype.to!string).build();
		btn.onClick += {
			Contact curContact = ctc.ctc;
			if (curContact.type != ctype)
			{
				curContact.type = ctype;
				Game.ciccon.sendMessage(immutable CICContactUpdateReq(curContact));
			}
		};
		classifications ~= btn;
	}
	NestedContextBtn classifySubmenu = builder(new NestedContextBtn(classifications, 20)).
		fontSize(15).content("classify as").build();
	res ~= classifySubmenu;
	return res;
}