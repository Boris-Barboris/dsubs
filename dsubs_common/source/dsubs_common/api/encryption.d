module dsubs_common.api.encryption;

// import std.algorithm: equal;
// public import std.base64: Base64;
// public import secured.rsa: RSA;


// private immutable string backendPubKey = `LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUF0MUxqSjdqam5VbDhBL1RCYU1nNwpKeng1QkhlNW1oVTVScEpmckpxc0tIOGg4c0NMSFduc2VMTWRQSEhTemo0RnFtdGhUSDR3NUhzUEhVc2JnTDhBCnFLL2NBT0ZIcExaeVVZd1grY0crVzllaHNXWDNWelUybkFNaUh1OUVORlN1VFJEMVVsZUMvbXM1TjBSWXdRQVkKR3ZYbklTRExhSDd3WWhNUWNYZWtabUwwUUk3bTlRam1kcEhlS3pmSnlPNzI0ajZwTFNkM2RDVitGS1pGdlJXNQpFNll1eXpaUkU0cElReHhuMng2K2grOHJRV3Qyb01NalRyc0xhK2ZwZ2dBRWpWQit0U3Voc1BadnJKU0dUSzE5ClpZK0I1dlJMY3I2Um4vQWRjK1B5U004WTc2R0JsTXNLTVlXVHhIeDlKV215U1dscG50RmNmNTJSbVdWSlhpVlQKSHdJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg==`;

// private RSA g_encryptor;

// /// Encrypt string with pinned backend RSA key.
// immutable(ubyte)[] encrypt(string data)
// {
// 	if (g_encryptor is null)
// 		g_encryptor = new RSA(Base64.decode(backendPubKey));
// 	return cast(immutable(ubyte)[]) g_encryptor.encrypt(cast(ubyte[]) data);
// }

// unittest
// {
// 	auto example = new RSA(2048);
// 	assert([5, 6].equal(example.decrypt(example.encrypt([5, 6]))));
// 	auto pub = example.getPublicKey();
// 	auto priv = example.getPrivateKey(null);
// 	assert(pub.equal(Base64.decode(Base64.encode(pub))));
// 	assert(priv.equal(Base64.decode(Base64.encode(priv))));
// 	auto examplePub = new RSA(pub);
// 	auto examplePriv = new RSA(Base64.decode(Base64.encode(priv)), null);
// 	assert([5, 6].equal(examplePriv.decrypt(examplePub.encrypt([5, 6]))));
// }