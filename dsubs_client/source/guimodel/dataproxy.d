module dsubs_client.guimodel.dataproxy;

import dsubs_client.core.event;

// structure to hold instance of type DataType, wich may be manipulated
// by multiple controllers and needs to notify all views on every change.
// Mostly used by UI: multiple controls on different windows that edit one value.
// Writes are not synchronized, controllers are implied to never write
// simultaniously. We just need to update other views when data changes.
struct DataProxy(DataType)
{
    DataType data;

    this(DataType init_value)
    {
        data = init_value;
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

    // unsubscribe from data updates
    void unregister_reciever(void delegate() callback)
    {
        event -= callback;
    }
}
