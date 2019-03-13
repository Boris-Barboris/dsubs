module dsubs_client.game.contacts;

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

	void drop() {}
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

	private Contact m_ctc;
	@property const(Contact) ctc() const { return m_ctc; }
	alias ctc this;

	void drop() {}

	void addData(ClientContactData* cdata)
	{
		m_dataHash[cdata.id] = cdata;
		switch (cdata.source.type)
		{
			case DataSourceType.ActiveSonar:
				if (m_sonarDispEl !is null)
				{
					if (m_sonarDispEl.data.time <= cdata.time)
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
	}

	void updateData(ClientContactData* cdata)
	{
		if (m_sonarDispEl !is null && m_sonarDispEl.data is cdata)
			m_sonarDispEl.updateFromData();
	}

	void removeData(ClientContactData* cdata)
	{
		m_dataHash.remove(cdata.id);
		if (m_sonarDispEl.data is cdata)
			m_sonarDispEl.drop();
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
				m_contactHash[(*existing).ctcId].removeData(*existing);
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
}