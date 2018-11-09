module dsubs_common.api.constants;

/// Safety limit on message size (bytes)
enum int MAX_MSG_SIZE = 100000;	// 100 Kb

/// Time type, microseconds (1e-6 seconds)
alias usecs_t = long;