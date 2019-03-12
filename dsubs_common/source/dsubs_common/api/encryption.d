module dsubs_common.api.encryption;

import crypto.rsa;
public import crypto.rsa: RSAKeyInfo, RSA;


private immutable string backendPubKey = `AAAAQIhNNOl1mtHa10rEmT2cNlHRPpPnRZjbcKDVkxQ632xXvalu5FR+TBVntVprWNSWdU8+8eU9NEZTQM2J2+XCzwH+mw==`;

private RSAKeyInfo backendPubKeyInfo;
private bool pubKeyInited = false;

immutable(ubyte)[] encrypt(string data)
{
	if (!pubKeyInited)
	{
		// TLS
		backendPubKeyInfo = RSA.decodeKey(backendPubKey);
		pubKeyInited = true;
	}
	return cast(immutable(ubyte)[]) RSA.encrypt(backendPubKeyInfo, cast(ubyte[]) data);
}

string decrypt(ubyte[] data, RSAKeyInfo* privKeyInfo)
{
	return cast(string) RSA.decrypt(*privKeyInfo, data);
}

unittest
{
	import std.stdio;
	import std.conv: to;

	RSAKeyPair pair = RSA.generateKeyPair(512);
	writeln(pair);
	auto puk = RSA.decodeKey(pair.publicKey);
	auto prk = RSA.decodeKey(pair.privateKey);

	for(int i = 0; i < 16; i++)
	{
		string data = backendPubKey;
		ubyte[] en = RSA.encrypt(puk, cast(ubyte[]) data);
		ubyte[] de = RSA.decrypt(prk, en);
		if (!(cast(string) de == data))
		{
			writeln("crashed on iteration ", i);
			writeln(cast(string) de);
			assert(0);
		}
	}
}
