module dsubs_client.core.syncholder;

import std.algorithm;
import std.experimental.logger;

import dsubs_client.core.event;


alias ViewUpdateSignal = void delegate(Object);

// Class to hold instance of type DataType, wich may be manipulated
// by multiple controllers and needs to notify all views on every change.
// Mostly used by UI: multiple controls on different windows that edit one value.
// Writes are not synchronized, controllers are implied to never write
// simultaniously. We just need to update other views when data changes.
class SyncHolder(DataType)
{
    DataType data;

    this(DataType init_value)
    {
        data = init_value;
    }

    private Event!(ViewUpdateSignal) event;

    // subscribe to data updates
    void register_view(ViewUpdateSignal update_handler)
    {
        event += update_handler;
    }

    // send signal to subscribers that change_source has updated the data
    void signal_data_changed(Object change_source)
    {
        event.raise(change_source);
    }

    // unsubscribe from data updates
    void unregister_view(ViewUpdateSignal update_handler)
    {
        event -= update_handler;
    }
}
