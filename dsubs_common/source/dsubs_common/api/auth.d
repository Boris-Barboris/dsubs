// Authorization API

module dsubs_common.api.auth;

import dsubs_common.api.utils;


enum AuthResponse: ubyte
{
    OK = 0,
    INVALID = 1,
    USERNAME_BUSY = 2,       // relevant for registration.
}

/// This unit requests authorization from the server.
/// After authorization succeeded, you don't need to send any more of those.
/// Authorization is done once for TCP connection.
struct AuthLoginRequest
{
    @MaxLenAttr(64) string username;
    @MaxLenAttr(64) string password;
}

/// Send this unit in order to register new account.
struct RegisterRequest
{
    @MaxLenAttr(64) string username;
    @MaxLenAttr(64) string password;
}

/// Server's response on authorization or registration request.
struct RegisterResponse
{
    AuthResponse response;
}
