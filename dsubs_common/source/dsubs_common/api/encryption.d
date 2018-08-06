module dsubs_common.api.encryption;

import crypto.rsa;
public import crypto.rsa: RSAKeyInfo, RSA;


private immutable string backendPubKey = `AAABAJPL2uFvPdhups3a/ZFvv9lyZRaR0SbWsfLln8s4hqXDNOw8OWYnmPaNu5bsvDSAfccT4BatH8MR92nuBYAy0Nny7E6Tzs0MWZfj/zIGd4XWqIbq0WKsSosa3xSPmL1+0LmDcLg9NnWgeUjNWfNUvGnANm1XqbVvQeCkRhq3p91eftOYkS/jyTwszZZKOVyW4DkP4hk9+jY5w5860VYKBxE9ClPA8LCeBWIf6PUAXZxP722Gqdgg7cAbMdmbgjs7BhuWC7do4Rk7Pric7+VFp/A7noDMYW+mby+n5OYSS5G7RN6yRlit9QVFfYlqfJzCwu6yKTYelmCFH2hESNr8flH/2Q==`;
private __gshared RSAKeyInfo backendPubKeyInfo;

shared static this()
{
	backendPubKeyInfo = RSA.decodeKey(backendPubKey);
}


immutable(ubyte)[] encrypt(string data, RSAKeyInfo* pubKeyInfo = &backendPubKeyInfo)
{
	return cast(immutable(ubyte)[]) RSA.encrypt(*pubKeyInfo, cast(ubyte[]) data);
}

string decrypt(ubyte[] data, RSAKeyInfo* privKeyInfo)
{
	return cast(string) RSA.decrypt(*privKeyInfo, data);
}

unittest
{
	import std.stdio;
	import std.conv: to;

	RSAKeyPair pair = RSA.generateKeyPair(2048);
	string data = "123test";
	ubyte[] en = RSA.encrypt(RSA.decodeKey(pair.publicKey), cast(ubyte[]) data);
	writeln("encrypted 7-byte data size: ", en.length);
	ubyte[] de = RSA.decrypt(RSA.decodeKey(pair.privateKey), en);
	assert(cast(string) de == data);
}