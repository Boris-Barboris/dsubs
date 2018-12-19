module dsubs_common.containers.circqueue;


/// Fixed-capacity queue backed by circular buffer
struct CircQueue(T)
{
	private
	{
		T[] arr;
		size_t ifront = 0;
		size_t len = 0;
	}

	this(size_t size)
	{
		assert(size > 0);
		arr.length = size;
	}

	/// Number of elements waiting in the queue
	@property size_t length() const { return len; }

	@property size_t capacity() const { return arr.length; }

	/// Oldest element in the queue
	@property ref T front()
	{
		assert(len > 0);
		return arr[ifront];
	}

	void popFront()
	{
		assert(len > 0);
		ifront = (ifront + 1) % capacity;
		len--;
	}

	/// returns reference to the inserted value
	ref T pushBack(T val)
	{
		assert(len < capacity);
		size_t backIdx = (ifront + len) % capacity;
		arr[backIdx] = val;
		len++;
		return arr[backIdx];
	}
}