module dsubs_common.api.constants;

/// API version of this particular dsubs_common.api package.
/// MUST be incremented on each change.
immutable uint API_VERSION = 1;

/// Type that is used to uniquely identify ingame objects.
alias ID_TYPE = uint;

/// Time type, microseconds (1e-6 of a second)
alias USECS = ulong;
