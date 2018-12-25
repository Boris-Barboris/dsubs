module dsubs_server.connections.playercon;

import std.socket;

import core.atomic;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.encryption;
import dsubs_common.network.connection;

import dsubs_server.common;
import dsubs_server.player;


private immutable string backendPrivKey =
`LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2Z0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktnd2dnU2tBZ0VBQW9JQkFRQzNVdU1udU9PZFNYd0QKOU1Gb3lEc25QSGtFZDdtYUZUbEdrbCtzbXF3b2Z5SHl3SXNkYWV4NHN4MDhjZExPUGdXcWEyRk1makRrZXc4ZApTeHVBdndDb3I5d0E0VWVrdG5KUmpCZjV3YjViMTZHeFpmZFhOVGFjQXlJZTcwUTBWSzVORVBWU1Y0TCthemszClJGakJBQmdhOWVjaElNdG9mdkJpRXhCeGQ2Um1ZdlJBanViMUNPWjJrZDRyTjhuSTd2YmlQcWt0SjNkMEpYNFUKcGtXOUZia1RwaTdMTmxFVGlraERIR2ZiSHI2SDd5dEJhM2Fnd3lOT3V3dHI1K21DQUFTTlVINjFLNkd3OW0rcwpsSVpNclgxbGo0SG05RXR5dnBHZjhCMXo0L0pJenhqdm9ZR1V5d294aFpQRWZIMGxhYkpKYVdtZTBWeC9uWkdaClpVbGVKVk1mQWdNQkFBRUNnZ0VCQUlMdno5RDZUSkIyQVA3dVhRb1RJYlRuaTJRMmd6bGJlVm8vaDloSGJUbEwKZkpyZkRUM0gveDlDaDFvNXppQ0N5aGNydFFZbWg1TlpsYlVOaFNwU3dneTU5c0FtSjc2c2xVQkxlSUJwOGlXMQpBUWNzMWhuU3B4dU5YVnlNOXNFTnpxUzZ2UTIvOVk3MFZKeDEwNUtlRjVtQ0UwQmxKUU9RenU2dHdTdmFFWEVTCmZIekFvc1QrZUNPUStEV2RjcGdEUW9Wc3Y1MkJlNXh4ZldwUCtjVlhrSDZxSm1kTHJMRU5vWDFyZnAyVG04em0KZWJkRjFDdUpBZFUwdExDZ0w5ZURyaWlyRWVxWWp1SWMyYnloZ09GL21JK0dPaVZxQUQ5OUhoZk55MmhGd0VsaAp2dDgyeWh3b2tHdlg5eUlST1BnREtscXplVWlSKzB2RVAxM25LMTF5L25FQ2dZRUE1VjBueURSdHR1bjhWWTF5CmJBSjRlRWtJdVoveEJBSWdKcmhTTEkzbXd1b0FVaDVQbWFMN0c3dmN1UHNxNHBCd21yZEcra1NITTc4dVRzZTEKbW1WU0hCNHRHY094SWVZdHRiQWsrUFFjREZBVnZmSDdsNW1KREVhZUUwSUxvY2htMnFKSkRld1VPRkpUZ2I5ZAptNG9pREMzZ2RORU5RaXM1MFlvMzJvVGRhSWNDZ1lFQXpKejlBelpiMExpc3hIQlkxOWR3aGw4bnlZSHprR1MxCmJFd1ZWZFdMVFRldThobkREWlY4QTFBNitWelhtcW5xSmVmZzk5ZjI3bFE4TWVyajBnUFdEQVpTcm8yR0czbTIKYkNkVC9FTndTeWswSCtTeDRXR0hPRGcwd2VqOXVaMmQvSFh0ZHZ3SCs0bkhNZFZNSmZVUERhUi9OMHZKbXYxegpiMGZrMWVqSW5xa0NnWUExencvNU1RdVlRUGFZMzVFN2M2enRrenkveDUwVWNxYzJUa0hCQUIxbUZ0MnlaamdJCmRDcnpDN1N4bFFNdm1mRkE2c1IxREVTbnlDOUYvaVpGcllXQTRUZDFkdXFFYUdySzJDTWtZS2gvM3YzcXpPMVkKV0lYRlluL05SczVSeXlFT0k4cDl3S2ZSdXNhcWhzbWdKdHpyL0l0Ty9JaGV3S05VM0ZkVUpaMkgyd0tCZ0FPKwpUNGF5aE9XQnEyK0FtcStBT29mS3orQ0k1eHJhTE5PSlpNNklOSjg2Q0pKWFZGRTRUZWVGblQ2WXF6MGlKSzJDCjI0UE5TTEE5akVoaGdyK0I0SFdoMi90ampYT05PNEFwREFsT2RveDVlWUduM25WQUlvZ3R4eEZSSU9zM2JmK0QKYk0vRGRxWHNkRjkrQm9HZlJTSTd3elFReCtSMUJKcWhseGN1eGhUWkFvR0JBSjRtUWRnRzZVY3p1MUVZczdzZQpkVW5sQUNoL2x6K1lUYUFqNkJRcnM4ODUydWRZV3NCRlpEOWNzeTdLSWZPam03ZStyTVlCeS9wSHNFdzVCc21nClVaMWNYWHJNWFFLeitPK0g3cVJYUkZJSzFjQStsWDE5d2Q5aXJGUjZaV2xmQjVKbFoyU01WdVk0T3J6ZDBVTHEKUVdkN1d3Vm5nQjROZWN0V0pGZlp3UXlTCi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0K`;

private RSA g_decryptor;

private string decrypt(ubyte[] data)
{
	if (g_decryptor is null)
		g_decryptor = new RSA(Base64.decode(backendPrivKey), null);
	return cast(string) g_decryptor.decrypt(data);
}


final class PlayerConnection: ProtocolConnection!BackendProtocol
{
	private
	{
		Player m_player;
		bool m_simulatorFlow;
	}

	@property Player player() { return m_player; }
	@property void player(Player rhs) { m_player = rhs; }

	@property bool simulatorFlow() const { return m_simulatorFlow; }

	this(Socket sock)
	{
		super(sock);
		setHandler(&h_serverStatus);
		setHandler(&h_loginReq);
		setHandler(&h_entityDbReq);
		setHandler(&h_spawnReq);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
		setHandler(&h_reconnectReq);
		setHandler(&h_listenDirReq);
		setHandler(&h_emitPingReq);
	}

private:

	void h_serverStatus(ServerStatusReq req)
	{
		// instantly reply with status message
		sendMessage(immutable ServerStatusRes(Player.getPlayersOnline()));
	}

	void h_loginReq(LoginReq req)
	{
		enforce!AuthException(m_player is null, "already authorized");
		try
		{
			m_player = Globals.players.authorizeConnection(this,
				req.username.decrypt(),
				req.password.decrypt());
			if (m_player.submarine)
			{
				// we are already spawned
				sendMessage(immutable LoginRes(true, "Welcome",
					Globals.entityDb.commonEntityDbHash, true));
			}
			else
			{
				// we have no submarine
				sendMessage(immutable LoginRes(true, "Welcome",
					Globals.entityDb.commonEntityDbHash, false));
			}
		}
		catch (AuthException aex)
		{
			sendMessage(immutable LoginRes(false, aex.msg,
				Globals.entityDb.commonEntityDbHash, false));
		}
	}

	void h_entityDbReq(EntityDbReq req)
	{
		sendBytes(Globals.entityDb.marshalledCommonEntityDb);
	}

	void h_spawnReq(SpawnReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		immutable(ReconnectStateRes) rres = p.handleSpawnRequest(req);
		sendMessage(immutable SpawnRes(true));
		sendMessage(rres);
		m_simulatorFlow = true;
	}

	void h_reconnectReq(ReconnectReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		synchronized(Globals.simMut.reader)
		{
			sendMessage(p.getReconnectState());
			m_simulatorFlow = true;
		}
	}

	void enforceAuthAndSim(Player p)
	{
		enforce!AuthException(p, "unauthorized");
		enforce!Exception(m_simulatorFlow, "not in simulator flow");
	}

	void h_throttleReq(ThrottleReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleThrottleRequest(req);
	}

	void h_courseReq(CourseReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleCourseRequest(req);
	}

	void h_listenDirReq(ListenDirReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleListenDirRequest(req);
	}

	void h_emitPingReq(EmitPingReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleEmitPingRequest(req);
	}
}