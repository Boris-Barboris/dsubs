module dsubs_common.containers.circqueue;


/// Fixed-capacity queue backed by circular buffer
struct CircQueue(T, size_t size)
{
	private
	{
		T[size] arr;
		size_t ifront = 0;
		size_t len = 0;
	}

	@property size_t length() const { return len; }
	enum size_t capacity = size;

	@property ref T front()
	{
		assert(len > 0);
		return arr[ifront];
	}

	void popFront()
	{
		assert(len > 0);
		ifront = (ifront + 1) % size;
		len--;
	}

	/// returns reference to the inserted value
	ref T pushBack(T val)
	{
		assert(len < size);
		size_t backIdx = (ifront + len) % size;
		arr[backIdx] = val;
		len++;
		return arr[backIdx];
	}
}