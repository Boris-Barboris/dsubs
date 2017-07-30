Common:
	API units defined in dsubs_common.
	Common byte stream marshalling of API units defined in dsubs_common as well.
	Networking and API constants defined in dsubs_common.

Engine:
	No embedded scripting language, D is flexible enough.
	Need 2d shapes rendering.
	2d collision detection for server.

Memory management:
	We'll start with GC-only game.
	If it proves to bee stuttery, we'll switch to RAII and manual memory
	management. Biggest problem by far is Phobos, especially threading classes.
	Thankfully, we're not on embedded platform, and we can use both GC and manual
	management simultaniously.

GUI:
	I need markup-alike elemnet placing scheme, for fast and scalable UI creation.
	I need basic functionality of:
	+ div.
	+ Simple label.
	+ Button.
	+ Toggle.
	+ Text field (editable).
		+ insert inputed symbol at caret.
		+ replace selected symbols by inputs.
		+ delete and backspace handling.
		+ horizontal scroll by mouse wheel (wich moves caret) and caret movement.
		+ caret moving my left\right keys.
		+ selection moving my shift+left\right keys.
		+ handle end and home keys.
		+ handle ctrl+a.
	+ Password textfield (characters hidden).
	? Text box (readonly, multiline). Has a scroll bar, word wrap.
		- word wrap.
		+ symbol wrap - very ugly, but works and easy to write.
		+ if box is too small, wrap by characters.
		+ tab character correctly displayed.
		+ vertical scroll by mouse wheel.
		+ scroll bar (implemented as composite).
	? ScrollBar composite
		+ mousewhell scroll
		? horizontal scroll
		+ reaction to underlying element size change
		+ event propagation to underlying element
	? Window - essentialy, floating closable div. Maybe even resizable.
		- out-of-screen protection
		- close button
		- dragging
	- Image - generic render target to display graphical information.
		No need for fancy scaling or zooming, just display image, no matter how
		warped.
	- dropdown list.
	- context menu (nested) - like those that you see after right-clicking
		something. Usefull for interactions with overlay elements.
	- CheckBox
	+ use viewport to force element boundaries and provide guaranteed
		overlap protection. May be expensive on OpenGL side. Benefits only
		labels and buttons, probably not worth it. Obligatory for text box.
	+ Control content cannot dictate control size, because such scheme always
		backfires (HTML is a good example).
	+ input focus handling, capturing.
	+ before\after GuiRender event.
	+ unicode support for onscreen text.
	- all elements support correct dynamic creation, disabling, enabling, deletion.
	+ hierarchical viewport framework.
	? element's content size.
		+ CONTENT size_type was added, such element controls it's own size.
	- proper event and layout architecture description.
	- tooltips

System and utility:
	- unicode mutstring support for logging.

On mouse input:
	GUI elements are static, it's reasonable to handle mouse events only when
	they are generated. World-space objects move themself, they can leave immobile
	cursor behind. That's why render is expected to generates artificial
	mouseMove event on each render cycle for focused window.

Input-related stuff:
	Mouse moved. May generate:
		mouse entered or left component area of interest. OnMouseEnter, OnMouseLeave.
		We simply generate mouse moved event in render cycle since mouse hover
		is tightly coupled to view, and look for the element under cursor every
		screen update.
	Mouse button or wheel pressed\scrolled. May trigger input focus switch:
		onClick... onFocusGain, onFocusLoss.
	Router:
		Entity that handles events of one window. Routes events to recievers in
			some specific order.
	Subrouter:
		Input event subrouter of the particular subsystem.
		There are currently 4 of those in the router:
			gui, overlay, world, hotkey.
	All input-event recievers can posess three focuses:
		cursorFocus - reciever's visual representation is under mouse cursor.
			Only makes sence for visible recievers.
		mouseFocus - all mouse events are first passed to focused reciever, and
			then discarded.
		keyboardFocus - all keyboard events are first passed to focused reciever,
			and may then be passed to subrouters, if the focused reciever
			desires.
	Component moved:
		may leave static mouse cursor behind, or stumble upon it. OnMouseEnter,
		OnMouseLeave.
	Keyboard input: goes either to focused element, or to subrouter cascade.

Render general:
	? world-space and screen-space object updates can in theory be parallelized,
		by means of rendering in two textures: (world + overlay) and (gui),
		and then merge those two textures on window. It can also reduce loads
		on the GPU, because GUI can be modified to render only when something
		has changed. I'll not go that far from the start, only if some performance
		issues will arise.
	+ Rewrite camera to use inbuilt sfml view, since manually multiplying matrixes
		on CPU is wasteful. There already is double-matrix gpu schema, no need to
		ignore it.
	- FPS counter (can easily by done on UI level) and profiling.

World-space render:
	+ Simple convex shape rendering.
	? transform update loop can be paralellized, if task may actually become
		quite heavy for one thread.
	- spacial optimization, camera-bound culling, object lookup for picking.
	+ world-space and overlay-space renders are shared between windows,
		because they manage the same set of objects, existing in one space.
		Gui render, on the other hand, is different for each window.
		Hence they should manage window context (camera, optimization structures)
		on their own. Need to aggregate all this stuff to some utility classes.

Overlay-space render:
	- Simple shape rendering.
	- spacial optimization, camera-bound culling, object lookup for picking.
	- overlay-space objects in dsubs can well be huge line segments.
		When both ends of the segment are outside the screen, it doesn't mean that
		points inbetween are not. You need to be careful when implementing culling,
		maybe it's ok to not cull at all. Picking should be bound to segment
		ends, or some discrete key points, wich means it's easier to implement.

Spacial hashing:
	We're in 2d space, so let's use quadrtree (sparse). Contained element - AABB.
	Each renderable entity should expose an interface to get it's bounding box.
	Camera view frustrum is bounded as well - that's how we get elements to draw.
	Not only leafs of a tree can contain elements, but even the root:
	this is helpful when object sizes are unbounded.
	GUI elements move or change rarely. World-space objects, on the other hand,
	do so frequently, many of them do so every frame. Tree update must be fast.
	Caching is a must. Also, we're not forced to have a fixed tree root, when we're
	out of bounds, we can just build a new upper layer and shift the root up.


Game mechanics:
	Modular ship design.
	Parts:
		Hull:
			Structure - weight vs robustness.
			Shell layer - armor vs sound insulation vs weight.
			Covering layer - armor vs friction reduction vs active sonar signature vs weight.
		Power source:
			Fueled - generate power by fuel consumption. Loud, requires refueling
				in special places on the map.
			Accumulator - capacitor, essentialy. Noiseless.
			Eternal - "nuclear" analog. Big, low to moderate noise. Different
				flavors:
				- standard, low inertia, medium power.
				- molten metal, medium inertia, low noise, medium power, low robustness.
				- supercharged, high inertia, medium noise, highest peak power.
		Propulsion:
			Screws, Pump jest, memes (supersized turbines):
				- Thrust to rpm relation.
				- Thrust to speed relation.
				- Noise to rpm relation.
				- Noise to speed relation.
				- Moment of inertia.
		Passive sonars:
			matrix resolution.
			view angle.
			Aperture, focal strength (quality of signature analisys).
			Frequency corridor.
			Signal noise in vacuum.
			Own ship noise sensitivity.
			Carrier speed-noise relation.
			"Phantoms", directional ambiguity.
			Breakoff speed (for towed arrays).
		Active sonars:
			view angle.
			matrix resolution.
			Signal noise in vacuum.
			Own ship noise sensitivity.
			Carrier speed-noise relation.
			Radiation power (+-editable).
		Active interceptors:
			view angle.
			matrix resolution.
			Signal noise in vacuum.
			Own ship noise sensitivity.
			Carrier speed-noise relation.
		Silos:
			Reload speed vs launch noise vs max operating speed.
		Weapon racks:
			Reload speed vs noise vs stock size.
		Countermeasures:
			Passive jammers
			Directed jammers
			Decoys
			Signature alterators


User interaction scenarios:

	User starts dsubs via executable, if it exists. It opens one window.

	User can start dsubs with shipped shell script, that uses dub to recompile
		the client. Usefull for modders or programmers that don't mind
		hacking.

	Main menu is full of functionality to quckly start playing:
		Connection section, wich allows to quickly login and play:
			text box with server status.
			login text field that holds previous login.
			password field.
			checkbox wich allows to save the password.
			connect button.
			label to report errors.
		...
	Main menu can be "scrolled" left\right to switch to other tabs, such as:
		Manual:
			Spoiler-alike list of manual sections with pictures.
		Settings:
			Various game settings, key bindings etc...

	After successfull connect user sees:
		text box containing server's
			welcome string. It may report number of players, active map,
			weather conditions, anything actually.
		Button 'OK'

	After clicking OK user is on loadout screen, where he chooses his ship,
		Sizable section of the screen with actual rendered representation of
			the submarine.
		Drop-down list of available submarines.
		Scrollable list wich contains all slots wich can be occupied, each
			represented with it's name and drop-down list of names of modules
			wich can be fitted (and empty element if applicable).
		Section to choose armament. Consists of scrollable list of all ammunition
			compatible with current loadout and numeric text fields, dictating
			number of "siguars".
		Spawn button.
		Label to output server's response on spawn request, or to state respawn
			cooldown countdown.

After clicking "Spawn" button and waiting a little user is in main Game mode.
Let's list all user interaction scenarios:

	set desired course.
		- set course with mouse: press hotkey, move cursor in
			desired direction (line is drawn) and release hotkey to apply course.
		- set course numerically in text field. Pair of text field and label to
			display current course.
	set desired propulsor power consumption [-1, 1] (relative to max).
		- set rpm with mouse: press hotkey and move mouse, while looking at
			the bar.
		- set rpm numerically like in a previous case.
	get information about current course\speed.
		- overlay elements, small "tails" around icons of ships that give the
			notion of it's course and speed.
		- textual representation. Labels with readouts right beside textboxes to
			set desired values.
	get information about map.
		- in all overlays you should see map bounds rectangle.
	camera control.
		- limited zoom with moue wheel.
			Not closer than some value. allows to see whole map.
		- cursor position moves camera center while zooming.
		- mouse-only panning by dragging with RMB pressed.
		- mouse-only camera rotation.
		- north-south arrow icon in UI to keep track of orientation.
	map grid.
		- small icon to toggle map grid.
		- grid resolution varies with zoom level
		- small ruler to keep track of the scale
	create, delete and classify contacts.
	view passive sonar output (waterfall).
	assign contact to passive sonar signal.
	manage binding between contact and signal.
	manage (create, move, delete) data points.
	assign inbuild AI to track signals.
	control active sonar. single ping, continuous ping. directional options.
	manage data points on active sonar data history.
	manage tube loadout.
	view data on contacts in visual and textual form.
	manual or semi-automatic TMA for contacts.
	setup loaded munition
	fire loaded munition
	view damage report and damage control information
	manage miscelanous modules:
		activate\deactivate jammers
		steer focused jammers
		retrieve\extend towed sensors
		control propulsion\energy systems
		...
