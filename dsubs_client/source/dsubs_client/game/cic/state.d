module dsubs_client.game.cic.state;

import std.array: array;
import std.algorithm: map;
import std.ascii: isUpper;

import core.sync.mutex: Mutex;
import core.sync.condition: Condition;

import dsubs_common.api.protocols.backend;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.entities;
import dsubs_client.common;


/**
In-memory database for CIC server. CICState is born when the client spawns in
game world and is destroyed only on the next spawn or when the process dies.
Important data is periodically dumped to disk in order to be able to survive
CIC server crash.
*/
final class CICState
{
	private
	{
		ReconnectStateRes m_recState;
		Condition m_recStateCond;
		bool m_recStateInitialized;
		Mutex m_rsMut;
	}

	this()
	{
		m_rsMut = new Mutex();
		m_recStateCond = new Condition(m_rsMut);
		m_ctcMut = new Mutex();
	}

	/// Main reconnect state mutex. Serialized reconnect state operations.
	@property Mutex rsMut() { return m_rsMut; }

	/// Timestamp of the last kinematic snapshot, received from the server.
	@property usecs_t lastSimTime() const { return m_recState.subSnap.atTime; }

	@property immutable(ReconnectStateRes) recState() const
	{
		return cast(immutable) m_recState;
	}

	/// You must hold rsMut when entering this method
	@property immutable(CICReconnectStateRes) awaitCicRecState()
	{
		if (!m_recStateInitialized)
			m_recStateCond.wait();
		assert(m_recStateInitialized);
		const CICReconnectStateRes res = const CICReconnectStateRes(
			m_recState,
			m_ctcCtxHash.byValue.map!(ctx => ctx.ctc).array);
		return cast(immutable) res;
	}

	/// false until the very first reconnect state received from backend
	@property bool recStateInitialized() const { return m_recStateInitialized; }

	void handleReconnectStateRes(ReconnectStateRes res)
	{
		assert(!m_recStateInitialized);
		synchronized(m_recStateCond.mutex)
		{
			m_recState = res;
			m_recStateInitialized = true;
			m_recStateCond.notifyAll();
		}
	}

	void handleSubKinematicRes(SubKinematicRes res)
	{
		m_recState.subSnap = res.snap;
	}

	void handleThrottleReq(CICThrottleReq req)
	{
		m_recState.targetThrottle = req.target;
	}

	void handleCourseReq(CICCourseReq req)
	{
		m_recState.targetCourse = req.target;
	}

	void handleListenDirReq(CICListenDirReq req)
	{
		enforce(req.hydrophoneIdx >= 0 && req.hydrophoneIdx < m_recState.listenDirs.length);
		m_recState.listenDirs[req.hydrophoneIdx] = req.dir;
	}

	/// Contact and it's data.
	private struct ContactContext
	{
		Contact ctc;
		ContactDataTree dataTree;	/// time-ordered data tree of this contact
	}

	// contacting-related state
	private
	{
		Mutex m_ctcMut;
		/// ctcId-hashed table of all contact contexts
		ContactContext*[ContactId] m_ctcCtxHash;
		/// contact id sequence generators
		int['Z' - 'A' + 1] m_contactPostfixes;
		/// dataId sequence generator
		int m_dataIdSeq = -1;
		/// id-hashed table of all contact data
		ContactData*[int] m_ctcDataHash;
	}

	/// Main contacting system mutex, provides contacting state serialization.
	/// Must not be taken after rsMut to prevent deadlocks.
	@property Mutex ctcMut() { return m_ctcMut; }

	/// Allocate, initialize and register new Contact entity.
	Contact* createContact(char prefix)
	{
		enforce(isUpper(prefix), "capital latin letters only");
		size_t sprefix = (prefix - 'A').to!size_t;
		if (m_contactPostfixes[sprefix] == int.max)
			assert(0, "sequence overflow");
		m_contactPostfixes[sprefix]++;
		Contact resctc = Contact(ContactId(prefix, m_contactPostfixes[sprefix]));
		synchronized (m_rsMut)
		{
			resctc.createdAt = lastSimTime;
		}
		resctc.solution.time = resctc.createdAt;
		ContactContext* resCtx = new ContactContext(resctc, new ContactDataTree());
		m_ctcCtxHash[resctc.id] = resCtx;
		return &resCtx.ctc;
	}

	/// Returns null if the contact or the data being updated does not exist
	ContactData* updateOrCreateData(ContactData newData)
	{
		// verify that the contact exists
		ContactContext* ctcCtx = m_ctcCtxHash.get(newData.ctcId, null);
		if (ctcCtx is null)
			return null;
		if (newData.id >= 0)
		{
			// if we are updating the data, verify that it exists
			ContactData* existing = m_ctcDataHash.get(newData.id, null);
			if (existing is null)
				return null;
			// data contact may have been changed
			if (existing.ctcId != newData.ctcId)
			{
				// we need to remove the data from old contact
				ContactContext* oldctcCtx = m_ctcCtxHash[existing.ctcId];
				oldctcCtx.dataTree.removeKey(existing);
				existing.time = newData.time;
				existing.ctcId = newData.ctcId;
				ctcCtx.dataTree.insert(existing);
			}
			else if (existing.time != newData.time)
			{
				// timestamp differs, we need to reinsert it into the tree
				ctcCtx.dataTree.removeKey(existing);
				existing.time = newData.time;
				ctcCtx.dataTree.insert(existing);
			}
			existing.source = newData.source;
			existing.type = newData.type;
			existing.data = newData.data;
			return existing;
		}
		else
		{
			// new data sample
			if (m_dataIdSeq == int.max)
				assert(0, "sequence overflow");
			m_dataIdSeq++;
			ContactData* res = new ContactData(m_dataIdSeq, newData.ctcId, newData.time,
				newData.source, newData.type, newData.data);
			m_ctcDataHash[res.id] = res;
			ctcCtx.dataTree.insert(res);
			return res;
		}
	}

	/// Try to set initial solution of the contact based on one data
	void initializeSolution(Contact* ctc, ContactData* fromData)
	{
		assert(ctc.id == fromData.ctcId);
		ctc.solution.velAvailable = false;
		ctc.solution.time = fromData.time;
		if (fromData.type == DataType.Position)
		{
			ctc.solution.posAvailable = true;
			ctc.solution.posData = fromData.data.position;
		}
		else
			ctc.solution.posAvailable = false;
	}

	/// Update contact parameters
	bool updateContact(Contact from)
	{
		ContactContext* ctcCtx = m_ctcCtxHash.get(from.id, null);
		if (ctcCtx is null)
			return false;
		enforce(from.createdAt == ctcCtx.ctc.createdAt,
			"Contact createdAt is immutable");
		ctcCtx.ctc.comment = from.comment;
		ctcCtx.ctc.solution = from.solution;
		return true;
	}

	bool dropContact(ContactId ctcId)
	{
		ContactContext* ctcCtx = m_ctcCtxHash.get(ctcId, null);
		if (ctcCtx is null)
			return false;
		m_ctcCtxHash.remove(ctcId);
		// we need to remove all contactData of this contact
		ctcCtx.dataTree.clear();
		return true;
	}

	bool dropData(int id)
	{
		ContactData* data = m_ctcDataHash.get(id, null);
		if (data is null)
			return false;
		m_ctcDataHash.remove(id);
		ContactContext* ctcCtx = m_ctcCtxHash[data.ctcId];
		ctcCtx.dataTree.removeKey(data);
		return true;
	}

	bool mergeContacts(ContactId source, ContactId dest)
	{
		assert(source != dest);
		ContactContext* sourceCtx = m_ctcCtxHash.get(source, null);
		if (sourceCtx is null)
			return false;
		ContactContext* destCtx = m_ctcCtxHash.get(dest, null);
		if (destCtx is null)
			return false;
		foreach (ContactData* data; sourceCtx.dataTree[])
		{
			data.ctcId = dest;
			destCtx.dataTree.insert(data);
		}
		sourceCtx.dataTree.clear();
		return m_ctcCtxHash.remove(source);
	}
}