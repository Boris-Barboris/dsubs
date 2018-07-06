/// CIC protocol messages
module dsubs_client.game.cic.messages;

import dsubs_common.api.protocols.backend;

public import dsubs_common.api.constants;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;


/// first message sent by client after connecting to CIC
struct CICLoginReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string password;
}

/// CIC server hello response that states the version
struct CICLoginRes
{
	__gshared const int g_marshIdx;
	int apiVersion = 1;
}

/// Messages that duplicate backend protocol messages
alias CICSubKinematicRes = SubKinematicRes;
alias CICThrottleReq = ThrottleReq;
alias CICCourseReq = CourseReq;