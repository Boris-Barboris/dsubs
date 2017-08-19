module dsubs_client.guimodel.callproxy;

import dsubs_client.core.event;


// Callproxy is used to synchronize long remote calles made by
// buttons.
struct CallProxy
{
    private bool _called = false;
    private void delegate() _call;  // call being guarded

    bool called() { return _called; }

    this(void delegate() method)
    {
        _call = method;
    }

    private Event!(void delegate()) event;

    // subscribe to data updates
    void register_reciever(void delegate() callback)
    {
        event += callback;
    }

    // send signal to subscribers that change_source has updated the data
    void signal()
    {
        event.raise();
    }

    void call()
    {
        assert(!_called);
        _called = true;
        signal();
        _call();
        _called = false;
        signal();
    }

    // unsubscribe from data updates
    void unregister_reciever(void delegate() callback)
    {
        event -= callback;
    }
}
