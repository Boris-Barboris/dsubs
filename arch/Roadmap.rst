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
    + Text field (editable).
        + insert inputed symbol at caret.
        + replace selected symbols by inputs.
        + delete and backspace handling.
        - horizontal scroll by mouse wheel and caret movement.
        + caret moving my left\right keys.
        + selection moving my left\right keys.
    - Text box (readonly). Has a scroll bar, word wrap.
    ? Window - essentialy, floating closable div. Maybe even resizable.
    - Image - generic render target to display graphical information.
        No need for fancy scaling or zooming, just display image.
    + use viewport to force element boundaries and provide guaranteed
        overlap protection. May be expensive on OpenGL side. Benefits only
        labels and buttons, probably not worth it. Obligatory for text box.
    + Control content cannot dictate control size, because such scheme always
        backfires (HTML is a good example).
    + input focus handling, capturing.
    + before\after GuiRender event.
    + unicode support for onscreen text.

System and utility:
    - unicode mutstring support for logging.

On mouse input:
    GUI elements are static, it's reasonable to handle mouse events only when
    they are generated. World-space objects move themself, they can leave immobile
    cursor behind.

Input-related event types:
    Mouse moved. May generate:
        mouse entered or left component area of interest. OnMouseEnter, OnMouseLeave.
        We simply generate mouse moved event in render cycle since mouse hover
        is tightly coupled to view, and look for the element under cursor every
        screen update.
    Mouse button or wheel pressed. May trigger input focus switch:
        onClick... onFocusGain, onFocusLoss.
    Component moved:
        may leave static mouse cursor behind, or stumble upon it. OnMouseEnter,
        OnMouseLeave.
    Keyboard input: goes either to focused element,
        or to subrouter cascade.

Render general:
    ? world-space and screen-space object updates can in theory be parallelized,
        by means of rendering in two textures: (world + overlay) and (gui),
        and then merge those two textures on window.

World-space render:
    + Simple convex shape rendering.
    - transform update loop should be paralellized, task may actually become
        quite heavy for one thread.
    - spacial optimization, camera-bound culling, object lookup for picking.
    - world-space and overlay-space renders are shared between windows,
        hence they manage window context (camera, optimization structures)
        on their own. Need to aggregate all this to some class.

Overlay-space render:
    - Simple shape rendering.
    - spacial optimization, camera-bound culling, object lookup for picking.

Spacial hashing:
    We're in 2d space, so let's use quadrtree. Contained element - AABB.
    Each renderable entity should expose an interface to get it's bounding box.
    Camera view frustrum is bounded as well - that's how we get elements to draw.
    Not only leafs of a tree can contain elements, but event the root (that makes
    an object always renderable), this is helpful when object sizes are unbounded.
    GUI elements move or change rarely. World-space objects, on the other hand,
    do so frequently, many of them do so every frame. Tree update must be fast.
    Caching is a must. Also, we're not forced to have a fixed tree root, when we're
    out of bounds, we can just build an upper layer and shift the root.
