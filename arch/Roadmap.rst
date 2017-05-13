Common:
    API units defined in dsubs_common.
    Common byte stream marshalling of API units defined in dsubs_common as well.
    Networking and API constants defined in dsubs_common.

Engine:
    No embedded scripting language, D is flexible enough.
    Need 2d shapes rendering.
    2d collision detection for server.

GUI:
    I need markup-alike elemnt placing scheme, for fast and scalable control placement.
    I need basic functionality of:
    + div.
    + Simple label.
    + Button.
    + Toggle.
    - Text field (editable).
    - Text box (editable). Has a scroll bar, word wrap.
    ? Window - essentialy, floating closable div. Maybe even resizable.
    - Image - generic render target to display graphical information.
        No need for fancy scaling or zooming, just display image.
    ? Maybe use viewport to force element boundaries and provide guaranteed
        overlap protection. May be too expensive on OpenGL side. Benefits only
        labels and buttons, probably not worth it.
    + Control content cannot dictate control size, because such scheme always
        backfires (HTML is a good example).
    - input focus handling, capturing.

World-space render:
    + Simple convex shape rendering.

Spacial hashing:
    We're in 2d space, so let's use quadrtree. Contained element - AABB.
    Each renderable entity should expose an interface to get it's bounding box.
    Camera view frustrum is bounded as well - that's how we get elements to draw.
    Not only leafs of a tree can contain elements, but event the root (that makes
    an object always renderable), this is helpful when object sizes are unbounded.
    GUI elements move or change rarely. Worl-space objects, on the other hand,
    do so frequently, many of them do so every frame. Tree update must be fast.
    Caching is a must. Also, we're not forced to have a fixed tree root, when we're
    out of bounds, we can just build an upper layer and shift the root.
