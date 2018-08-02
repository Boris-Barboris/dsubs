module dsubs_client.game.cic.state;

import dsubs_common.api.protocols.backend;
import dsubs_client.game.cic.messages;
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
	}

	@property immutable(CICReconnectStateRes) recState() const
	{
		return cast(immutable CICReconnectStateRes) m_recState;
	}

	/// false until the very first reconnect state received from backend
	bool recStateInitialized() const { return m_recStateInitialized; }

	void handleReconnectStateRes(ReconnectStateRes res)
	{
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
}