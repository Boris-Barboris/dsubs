/// CIC protocol messages
module dsubs_client.game.cic.messages;

public import dsubs_common.api.constants;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;


/// first message sent by client after connecting to CIC
struct CICLoginReq
{
	__gshared const int g_marshIdx;
	int apiVersion = 1;
	@MaxLenAttr(64) string password;
}

/// CIC server response
struct CICLoginRes
{
	__gshared const int g_marshIdx;

}