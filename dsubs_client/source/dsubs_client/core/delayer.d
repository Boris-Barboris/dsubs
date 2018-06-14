module dsubs_client.core.delayer;

import std.container.rbtree;
import std.experimental.logger;

public import core.time;
import core.atomic;
import core.thread;
import core.sync.condition;
import core.sync.mutex;


/// Background thread wich dispatches delayed delegates
final class Delayer
{
	private struct DelayRecord
	{
		MonoTime when;
		void delegate() what;
		Mutex toLock;
	}

	private
	{
		Thread m_thread;
		Condition m_cond;

		alias RecordCollection = RedBlackTree!(DelayRecord, "a.when < b.when", true);
		RecordCollection m_records;
		DelayRecord[] m_addQueue;
		Mutex m_recordsLock;
		shared bool m_stop = false;
	}

	this()
	{
		m_cond = new Condition(new Mutex());
		m_records = new RecordCollection();
		m_recordsLock = new Mutex();
		m_thread = new Thread(&proc);
	}

	void start()
	{
		m_thread.start();
	}

	void stop()
	{
		if (!cas(&m_stop, false, true))
			return;
		m_cond.notify();
		m_thread.join();
	}

	/// execute delegate 'what' after 'after' time interval, while holding
	/// 'mutToHold' lock.
	void delay(void delegate() what, Duration after, Mutex mutToHold = null)
	{
		assert(what !is null);
		assert(after > Duration.zero);
		MonoTime now = MonoTime.currTime;
		synchronized (m_recordsLock)
		{
			m_addQueue ~= DelayRecord(now + after, what, mutToHold);
		}
		m_cond.notify();
	}

	private void proc()
	{
		Duration tillWakeup;
		while (true)
		{
			bool frontReached = false;
			if (tillWakeup == Duration.zero)
				m_cond.wait();
			else
				if (tillWakeup > Duration.zero)
					frontReached = !m_cond.wait(tillWakeup);
				else
					frontReached = true;
			if (atomicLoad(m_stop))
				break;
			synchronized (m_recordsLock)
			{
				foreach (rec; m_addQueue)
					m_records.insert(rec);
				m_addQueue.length = 0;
			}
			if (m_records.empty)
			{
				tillWakeup = Duration.zero;
				continue;
			}
			if (frontReached)
			{
				DelayRecord firstRecord = m_records.front;
				// actually run the code
				if (firstRecord.toLock)
					firstRecord.toLock.lock();
				try
				{
					firstRecord.what();
				}
				catch (Exception e)
				{
					error(e);
				}
				if (firstRecord.toLock)
					firstRecord.toLock.unlock();
				m_records.removeFront();
			}
			// setup next wakeup
			if (m_records.empty)
				tillWakeup = Duration.zero;
			else
				tillWakeup = m_records.front.when - MonoTime.currTime;
		}
	}
}