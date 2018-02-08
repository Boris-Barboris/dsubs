module dsubs_common.api.constants;

/// API version of this particular dsubs_common.api package.
/// MUST be incremented on each change.
immutable int API_VERSION = 1;

/// Safety limit on message size
immutable int MAX_MSG_SIZE = 1000000;	// 1 Mb

/// Type that is used to uniquely enumerate server-side objects
alias id_t = uint;

/// Time type, microseconds (1e-6 of a second)
alias usecs_t = long;
