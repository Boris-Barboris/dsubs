module dsubs_common.containers.circqueue;


/// Fixed-capacity circular buffer
struct CircQueue(T, bool canOverwrite = false)
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
		static if (!canOverwrite)
			assert(len < capacity);
		size_t backIdx = (ifront + len) % capacity;
		arr[backIdx] = val;
		len++;
		return arr[backIdx];
	}

	/// Get idx'th element (starting from zero), counting from the back of the queue
	@property ref T fromBack(size_t idx)
	{
		assert(idx < len);
		idx = (ifront + len - idx - 1) % capacity;
		return arr[idx];
	}
}