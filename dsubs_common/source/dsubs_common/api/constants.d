module dsubs_common.api.constants;

/// API version of this particular dsubs_common.api package.
/// MUST be incremented on each change.
enum int API_VERSION = 1;

/// Safety limit on message size
enum int MAX_MSG_SIZE = 1000000;

/// Type that is used to uniquely identify ingame objects.
alias id_t = uint;

/// Time type, microseconds (1e-6 of a second)
alias usecs_t = long;

/// Connection string to server
enum string SERVER_ADDR = "127.0.0.1:13337";
