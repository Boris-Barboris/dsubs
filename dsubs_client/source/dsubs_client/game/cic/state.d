module dsubs_client.game.cic.state;

import std.ascii: isUpper;

import core.sync.mutex: Mutex;

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
		CICReconnectStateRes m_recState;
		bool m_recStateInitialized;
		Mutex m_rsMut;
	}

	this()
	{
		m_rsMut = new Mutex();
		m_tgtMut = new Mutex();
	}

	/// Main reconnect state mutex. Serialized reconnect state operations.
	@property Mutex rsMut() { return m_rsMut; }

	/// Timestamp of the last kinematic snapshot, received from the server.
	@property usecs_t lastSimTime() const { return m_recState.subSnap.atTime; }

	@property immutable(CICReconnectStateRes) recState() const
	{
		return cast(immutable CICReconnectStateRes) m_recState;
	}

	/// false until the very first reconnect state received from backend
	@property bool recStateInitialized() const { return m_recStateInitialized; }

	void handleReconnectStateRes(ReconnectStateRes res)
	{
		static assert (CICReconnectStateRes.sizeof == ReconnectStateRes.sizeof);
		m_recState = cast(CICReconnectStateRes) res;
		m_recStateInitialized = true;
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

	/// Target and it's data.
	private struct TargetContext
	{
		Target tgt;
		TargetDataTree dataTree;	/// time-ordered data tree of this target
	}

	// targeting-related state
	private
	{
		Mutex m_tgtMut;
		/// tgtId-hashed table of all target contexts
		TargetContext*[TargetId] m_tgtCtxHash;
		/// target id sequence generators
		int['Z' - 'A' + 1] m_targetPostfixes;
		/// dataId sequence generator
		int m_dataIdSeq = -1;
		/// id-hashed table of all target data
		TargetData*[int] m_tgtDataHash;
	}

	/// Main targeting system mutex, provides targeting state serialization.
	@property Mutex tgtMut() { return m_tgtMut; }

	/// Allocate, initialize and register new Target entity.
	Target* createTarget(char prefix)
	{
		enforce(isUpper(prefix), "capital latin letters only");
		size_t sprefix = (prefix - 'A').to!size_t;
		if (m_targetPostfixes[sprefix] == int.max)
			assert(0, "sequence overflow");
		m_targetPostfixes[sprefix]++;
		Target resTgt = Target(TargetId(prefix, m_targetPostfixes[sprefix]));
		synchronized (m_rsMut)
		{
			resTgt.createdAt = lastSimTime;
		}
		resTgt.solution.time = resTgt.createdAt;
		TargetContext* resCtx = new TargetContext(resTgt, new TargetDataTree());
		m_tgtCtxHash[resTgt.id] = resCtx;
		return &resCtx.tgt;
	}

	/// Returns null if the target or the data being updated does not exist
	TargetData* updateOrCreateData(TargetData newData)
	{
		// verify that the target exists
		TargetContext* tgtCtx = m_tgtCtxHash.get(newData.tgtId, null);
		if (tgtCtx is null)
			return null;
		if (newData.id >= 0)
		{
			// if we are updating the data, verify that it exists
			TargetData* existing = m_tgtDataHash.get(newData.id, null);
			if (existing is null)
				return null;
			// data target may have been changed
			if (existing.tgtId != newData.tgtId)
			{
				// we need to remove the data from old target
				TargetContext* oldTgtCtx = m_tgtCtxHash[existing.tgtId];
				oldTgtCtx.dataTree.removeKey(existing);
				existing.time = newData.time;
				existing.tgtId = newData.tgtId;
				tgtCtx.dataTree.insert(existing);
			}
			else if (existing.time != newData.time)
			{
				// timestamp differs, we need to reinsert it into the tree
				tgtCtx.dataTree.removeKey(existing);
				existing.time = newData.time;
				tgtCtx.dataTree.insert(existing);
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
			TargetData* res = new TargetData(m_dataIdSeq, newData.tgtId, newData.time,
				newData.source, newData.type, newData.data);
			m_tgtDataHash[res.id] = res;
			tgtCtx.dataTree.insert(res);
			return res;
		}
	}

	/// Try to set initial solution of the target based on one data
	void initializeSolution(Target* tgt, TargetData* fromData)
	{
		assert(tgt.id == fromData.tgtId);
		tgt.solution.velAvailable = false;
		tgt.solution.time = fromData.time;
		if (fromData.type == DataType.Position)
		{
			tgt.solution.posAvailable = true;
			tgt.solution.posData = fromData.data.position;
		}
		else
			tgt.solution.posAvailable = false;
	}

	/// Update target parameters
	bool updateTarget(Target from)
	{
		TargetContext* tgtCtx = m_tgtCtxHash.get(from.id, null);
		if (tgtCtx is null)
			return false;
		enforce(from.createdAt == tgtCtx.tgt.createdAt,
			"Target createdAt is immutable");
		tgtCtx.tgt.comment = from.comment;
		tgtCtx.tgt.solution = from.solution;
		return true;
	}

	bool dropTarget(TargetId tgtId)
	{
		TargetContext* tgtCtx = m_tgtCtxHash.get(tgtId, null);
		if (tgtCtx is null)
			return false;
		m_tgtCtxHash.remove(tgtId);
		// we need to remove all targetData of this target
		tgtCtx.dataTree.clear();
		return true;
	}
}