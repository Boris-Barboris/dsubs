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

	mixin Readonly!(ContactData, "data");
	@property int id() const { return m_data.id; }
	@property ContactId contactId() const { return m_data.ctcId; }

	void drop() {}
}

/// Client representation of a contact object
final class ClientContact
{
	this(CICContactCreatedRes msg)
	{
		m_data = msg.newContact;
		ClientContactData* newData = new ClientContactData(msg.initialData);
		m_dataHash[newData.id] = newData;
		switch (msg.initialData.source.type)
		{
			case DataSourceType.ActiveSonar:
				m_sonarDispEl = new SonarDispContactDataElement(
					Game.simState.gui.sonardisp.overlay,
					newData,
					this);
				break;
			default:
				break;
		}
	}

	this(Contact ctc)
	{
		m_data = ctc;
	}

	private SonarDispContactDataElement m_sonarDispEl;

	/// collection of all data of this contact
	private ClientContactData*[int] m_dataHash;

	mixin Readonly!(Contact, "data");
	@property ContactId id() const { return m_data.id; }

	void drop() {}
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

	ClientContact get(ContactId id) { return m_contactHash[id]; }

	void handleContactCreatedRes(CICContactCreatedRes msg)
	{
		enforce((msg.newContact.id in m_contactHash) is null,
			"contact is supposed to be new");
		m_contactHash[msg.newContact.id] = new ClientContact(msg);
	}
}