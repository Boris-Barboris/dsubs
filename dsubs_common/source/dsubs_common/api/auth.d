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
    static header_t header = cast(header_t) "loginreq";
    @MaxLenAttr(64) string username;
    @MaxLenAttr(64) string password;
}

/// Send this unit in order to register new account.
struct RegisterRequest
{
    static header_t header = cast(header_t) "register";
    @MaxLenAttr(64) string username;
    @MaxLenAttr(64) string password;
}

/// Server's response on authorization or registration request.
struct AuthRegisterRequest
{
    static header_t header = cast(header_t) "authresp";
    AuthResponse response;
}
