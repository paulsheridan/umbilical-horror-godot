extends Node3D
## The ship beyond the bay: what only drones reach. Geometry is authored in
## `scenes/level/ship.tscn` (grouped into room containers); this controller
## owns doors, the loss wreck, and the gameplay data baked onto the scene.
##
## M1 layout (all graybox, unlit on purpose — the drone's status lamp and
## the scanner are the only eyes). Convention: z0 = the *north* (more
## negative) face, z1 = the south face:
##
##   vestibule  x -3.4..-1.2, z0=-6.4  z1=-5.4   (dock; south = bay wall)
##   leg A      x -3.4..-1.2, z0=-14.4 z1=-6.4   north run
##   bend B     x -3.4..1.4,  z0=-16.4 z1=-14.4  east jog + west nook
##   leg C      x -1.4..1.0,  z0=-25.6 z1=-16.4  north run to junction
##   junction   x -4.6..4.6,  z0=-32.6 z1=-25.6  pillars, toppled crate
##   spur (E)   x 4.6..9.0,   z0=-31.4 z1=-28.4  salvage wreck + ring mouth
##   galley stub(W) x -8.4..-4.6, z0=-30.0 z1=-28.4 pressure door face
##   galley     x -20.4..-8.4, z0=-34.4 z1=-24.0 crew mess + cold room
##
## M6 east annex: a full donut corridor wrapped around a large cafeteria.
##   north ring x 4.6..21.0, z -31.4..-28.4 (the spur is its west end)
##   east ring  x 19.2..21.0, z -31.4..-16.0
##   south ring x 4.6..21.0, z -17.6..-16.0
##   west ring  x 4.6..6.2,  z -31.4..-16.0
##   cafeteria  x 6.2..19.2, z -28.4..-17.6, arches on all four sides
##
## The donut has two mouths into the junction's east wall: the old spur
## opening (north ring) and a second opening at the west ring. Drive the
## loop or cut through the cafeteria; the patrol uses both.
##
## M6c: the Processor wing. A long, almost unlit hall runs east from the
## berth hall and opens into a feed chamber where the Collector's finds are
## piled in front of a pinned giant mouth on two legs.
##   proc hall  x 21.0..28.0, z -13.0..-10.4
##   proc room  x 28.0..33.0, z -15.4..-8.0
##
## Connective faces are left open by the run that owns the opening on the
## far side; explicit segment walls close the rest of the shared plane.
## Dock is (-2.0, 0.32, -5.9): euclid dock -> deep junction ~27 m, annex
## far corner ~34 m (inside the 36 m tether), galley stub ~8 m. The
## Processor pile sits at ~32 m, so a dropped bot can still drive home.

const Mats := preload("res://src/mats.gd")
const PickupProps := preload("res://src/ship/pickup_props.gd")

## The pickup model sits on its original anchor; the glowing marker floats
## above it, near the eye line of a drone on the deck. The cold-room shelf is
## boxed in by stacked crates, so the light needs to clear them to be seen.
const CAMERA_INDICATOR_Y := 0.62
const FLASHLIGHT_INDICATOR_Y := 1.12

var dock_pos := Vector3(-2.0, 0.32, -5.9)

# Galley door / objective constants (main drives from these).
const DOOR_CLOSED_Z := -29.2
const DOOR_OPEN_Z := -27.3
const DOOR_SPEED := 0.8    # m/s — the grind lasts ~2 s, loud the whole way
var GALLEY_DOOR_POS := Vector3(-8.65, 1.0, -29.2)
# The cold-room shelf where the drone flashlight add-on waits. The old ration
# errand is gone; this is the first equipment upgrade the player can fit.
var FLASHLIGHT_POS := Vector3(-18.5, 0.35, -32.7)
# The video-camera module lies on the *near* (west) lip of the wreck, not
# behind it: the spur is only 1.6 m wide and the wreck blocks the far half, so
# a rear-mounted module is outside the drone's reachable pickup envelope.
var CAMERA_POS := Vector3(6.45, 0.45, -29.75)  # video module on the wreck

# --- East annex (M6): donut + cafeteria -----------------------------------

# --- Berth wing (M6b): the crew's rooms, south of the annex ring -----------
#   link W   x 7.6..9.6,  z -16.0..-13.0  normal mouth into the south ring
#   crawl    x 12.6..13.8,z -16.0..-13.0  0.9 m service duct (drone only)
#   link E   x 16.6..18.6,z -16.0..-13.0  normal mouth (the big bodies' route)
#   hall     x 7.0..21.0, z -13.0..-10.4  berth corridor
#   cabins   z -10.4..-6.0: three berths + the Collector's ossuary
# The one movable deposit point for the Collector's old nest. Change this
# vector (and the matching nest geometry in _ossuary) to move the hoard.
var COLLECTOR_DEPOSIT := Vector3(19.8, 0.0, -7.2)

# --- Processor wing (M6c) --------------------------------------------------
# A long dark hall east of the berth hall, ending in the feed chamber.
const PROC_HALL_X0 := 21.0
const PROC_HALL_X1 := 28.0
# The Processor is pinned against the chamber's east wall. The pile the
# Collector now feeds sits between it and the hall mouth.
var PROCESSOR_POS := Vector3(32.1, 0.0, -11.7)
var PROCESSOR_PILE := Vector3(29.8, 0.0, -11.7)
# Where the Collector sets a carried bot down: at the pile, on the hall side,
# so the player has room to drive clear when the Processor reaches.
var PROCESSOR_DROP := Vector3(28.9, 0.32, -11.7)

# --- Zone 2: the Cold Hold (M7) -------------------------------------------
# An eight-metre umbilical runs north from the junction's north wall into a
# single open, pitch-black hold. The hold is authored as one room so the
# single flat floor collider can cover it without a second slab.
var zone2_threshold := Vector3(0.0, 0.32, -33.4)
var zone2_relay := Vector3(-2.0, 0.3, -40.4)
## The enlarged hold chains two more winch relays so every new hall/room stays
## inside the 36 m tether drum without raising MAX_TETHER.
var zone2_west_relay := Vector3(-32.0, 0.3, -53.0)
var zone2_north_relay := Vector3(0.0, 0.3, -69.0)
var zone2_spawns: Array = [
	Vector3(-20.0, 0.2, -58.0),
	Vector3(16.0, 0.2, -58.0),
	Vector3(-22.0, 0.2, -47.0),
	Vector3(6.0, 0.2, -62.0),
]
var crawler_setpiece := Vector3(21.0, 0.2, -47.0)
var crawler_grab := Vector3(21.0, 0.2, -62.0)
var collector_sacrifice := Vector3(29.4, 0.0, -11.7)
# Deck C: the engine room beyond the crawler hall's far opening. The engine
# relay sits in the throat so the 36 m drum covers the whole room without
# raising MAX_TETHER.
var engine_entry := Vector3(21.0, 0.2, -66.8)
var engine_relay := Vector3(21.0, 0.3, -66.2)
var engine_far_relay := Vector3(22.0, 0.3, -90.0)
var engine_stalker_spawn := Vector3(30.5, 0.2, -86.5)
const ZONE2_DOOR_CLOSED_Y := 1.1
const ZONE2_DOOR_OPEN_Y := 3.42
const ZONE2_DOOR_SPEED := 1.6
## Cabin panels are light; they slide about twice as fast as the galley door.
const LOUD_DOOR_SPEED := 1.7

var galley_door: CSGBox3D = null
var galley_door_open := false
var zone2_door: CSGBox3D = null
var zone2_door_open := false
var camera_module = null
var flashlight_pickup: Node3D = null
## The dynamic camera module left in a wreck (not the scene's authored one).
var _wreck_camera: Node3D = null
## Each entry: {root, indicator, base_y, phase, lamp}. The indicator is a child
## of the pickup root, so main's existing visible toggles hide it for free.
var _pickup_fx: Array = []
var wreck_pieces: Array = []   # spawned loss wreck, visual-only (never blocks)
var hide_spots: Array = []     # {center, half} footprints of low tables/beds
var ambush_spots: Array = []   # corners where the stalker can fold up and wait
## Places the tall bodies cannot squeeze through but a flat drone can. The
## stalker routes around these when pursuing (see stalker.gd).
var chokes: Array = []
## Loud cabin doors: sliding panels that post noise into NoiseBus.
var loud_doors: Array = []
## Scattered crew remains for the Collector. Each entry: {node, pos, taken}.
var remains: Array = []
## Where collected parts accumulate. A separate node so it can be moved.
var collector_pile: Node3D = null
## The Processor's feeding pile, in the new east chamber.
var processor_pile: Node3D = null
var _door_grind_t := 0.0
var _zone2_grind_t := 0.0
## Authored hall/engine practicals, gently breathing so the side hall reads as
## a place that still has power. Each entry: {node, base, phase}.
var _practicals: Array = []
## The one authored light that stutters. Resolved once in _ready: a recursive
## find_children per frame for a node that never changes was pure waste.
var _flicker_lamp: OmniLight3D = null


## Main calls this when the drone gets close to the door plane.
func open_galley_door() -> void:
	if galley_door_open:
		return
	galley_door_open = true
	if galley_door == null:
		return
	Sfx.play("thud", galley_door.global_position, -2.0)
	NoiseBus.emit_noise(galley_door.global_position, 0.55)


## The zone-2 airlock: a single heavy panel that lifts clear of the frame and
## stays open. It is deliberately loud once, then silent; a second crossing
## should never cost the player noise they did not choose.
func open_zone2_door() -> void:
	if zone2_door_open:
		return
	zone2_door_open = true
	if zone2_door == null:
		return
	Sfx.play("thud", zone2_door.global_position, 1.0)
	NoiseBus.emit_noise(zone2_door.global_position, 0.85)

## The scene is the source of truth for geometry. Resolve the named anchors and
## rebuild the gameplay lists from the metadata baked onto their nodes.
func _ready() -> void:
	# Placement is editor-owned: markers override the fallbacks below.
	dock_pos = _anchor("Dock", dock_pos)
	CAMERA_POS = _anchor("CameraSite", CAMERA_POS)
	FLASHLIGHT_POS = _anchor("Flashlight", FLASHLIGHT_POS)
	GALLEY_DOOR_POS = _anchor("GalleyDoorApproach", GALLEY_DOOR_POS)
	COLLECTOR_DEPOSIT = _anchor("CollectorDeposit", COLLECTOR_DEPOSIT)
	PROCESSOR_POS = _anchor("ProcessorPos", PROCESSOR_POS)
	PROCESSOR_PILE = _anchor("ProcessorPile", PROCESSOR_PILE)
	PROCESSOR_DROP = _anchor("ProcessorDrop", PROCESSOR_DROP)
	zone2_threshold = _anchor("Zone2Threshold", zone2_threshold)
	zone2_relay = _anchor("Zone2Relay", zone2_relay)
	zone2_west_relay = _anchor("Zone2WestRelay", zone2_west_relay)
	zone2_north_relay = _anchor("Zone2NorthRelay", zone2_north_relay)
	for i in 4:
		zone2_spawns[i] = _anchor("Zone2Spawn%d" % i, zone2_spawns[i])
	crawler_setpiece = _anchor("CrawlerSetPiece", crawler_setpiece)
	crawler_grab = _anchor("CrawlerGrab", crawler_grab)
	collector_sacrifice = _anchor("CollectorSacrifice", collector_sacrifice)
	engine_entry = _anchor("EngineEntry", engine_entry)
	engine_relay = _anchor("EngineRelay", engine_relay)
	engine_far_relay = _anchor("EngineFarRelay", engine_far_relay)
	engine_stalker_spawn = _anchor("EngineStalkerSpawn", engine_stalker_spawn)
	galley_door = _resolve("GalleyDoor") as CSGBox3D
	zone2_door = _resolve("Zone2Door") as CSGBox3D
	camera_module = _resolve("CameraModule")
	collector_pile = _resolve("CollectorPile") as Node3D
	processor_pile = _resolve("ProcessorPile") as Node3D
	_pickup_fx.clear()
	_dress_camera_pickup()
	_build_flashlight_pickup()
	hide_spots.clear()
	ambush_spots.clear()
	chokes.clear()
	loud_doors.clear()
	remains.clear()
	_scan_data(self)
	# The side hall and engine room are lit by a few weak practicals. They are
	# authored scene lights, not runtime builders; this only animates them.
	_flicker_lamp = _resolve("FlickerLight") as OmniLight3D
	_practicals.clear()
	var practical_names := [
		"CrawlerLampA", "CrawlerLampB", "CrawlerLampC",
		"CrawlerLampD", "CrawlerLampE", "CrawlerLampF",
		"HoldHallLampA", "HoldHallLampB", "HoldHallLampC",
		"HoldHallLampD", "HoldHallLampE", "HoldHallLampF",
		"EngineLampA", "EngineLampB", "EngineLampC",
		"EngineLampD", "EngineLampE", "EngineLampF",
		"EngineLampG", "EngineLampH", "EngineLampI",
	]
	for i in practical_names.size():
		var lamp := _resolve(practical_names[i]) as OmniLight3D
		if lamp != null:
			_practicals.append({
				"node": lamp,
				"base": lamp.light_energy,
				"phase": float(i) * 1.7,
			})


## Resolve a named gameplay node while ignoring Marker3D anchors, which may
## share a name (the ProcessorPile anchor and the pile node are siblings in
## different containers).
func _resolve(node_name: String) -> Node:
	for node in find_children(node_name, "", true, false):
		if not node is Marker3D:
			return node
	return null


## A small, real add-on on the cold-room shelf. It is world geometry (not a UI
## icon) so the player can see what they are collecting under a still flash;
## main hides it the moment a chassis takes it.
func _build_flashlight_pickup() -> void:
	var existing := _resolve("FlashlightPickup") as Node3D
	if existing != null:
		flashlight_pickup = existing
		existing.position = FLASHLIGHT_POS
		_attach_pickup_fx(existing, "flashlight")
		return
	var root := Node3D.new()
	root.name = "FlashlightPickup"
	add_child(root)
	root.position = FLASHLIGHT_POS
	flashlight_pickup = root
	_attach_pickup_fx(root, "flashlight")


## The scene's camera module is an authored CSG box. CSG combines its children
## into one brush, so a model parented under it would inherit the box's
## surface. Swap the brush for an empty Node3D at the same local transform:
## the pickup anchor and every show/hide call stay identical.
func _dress_camera_pickup() -> void:
	var root := _resolve("CameraModule") as Node3D
	if root == null:
		return
	if root is CSGShape3D:
		var wrapper := Node3D.new()
		wrapper.name = "CameraModule"
		wrapper.transform = root.transform
		var parent := root.get_parent()
		parent.remove_child(root)
		root.queue_free()
		parent.add_child(wrapper)
		root = wrapper
	camera_module = root
	_attach_pickup_fx(root, "camera")


## Build (or re-register, after a repeat _ready()) the model and the hovering
## marker on a pickup root. Position and pickup radius remain owned elsewhere.
func _attach_pickup_fx(root: Node3D, kind: String) -> void:
	var glow := PickupProps.FLASHLIGHT_GLOW if kind == "flashlight" \
			else PickupProps.CAMERA_GLOW
	if root.has_meta("pickup_fx_ready"):
		var existing := root.get_node_or_null("PickupIndicator") as Node3D
		if existing != null:
			_register_pickup_fx(root, existing, existing.get_node_or_null("Glow"))
		return
	root.add_child(PickupProps.model(kind))
	var indicator := PickupProps.indicator(kind, glow)
	var hover := FLASHLIGHT_INDICATOR_Y if kind == "flashlight" \
			else CAMERA_INDICATOR_Y
	indicator.position = Vector3(0.0, hover, 0.0)
	root.add_child(indicator)
	root.set_meta("pickup_fx_ready", true)
	_register_pickup_fx(root, indicator, indicator.get_node_or_null("Glow"))


## Append the bob/spin record for one marker. The phase comes from the current
## list length, so a re-registered pickup lands in the same slot it always did.
func _register_pickup_fx(root: Node3D, indicator: Node3D, lamp: Node = null) -> void:
	_pickup_fx.append({
		"root": root,
		"indicator": indicator,
		"base_y": indicator.position.y,
		"phase": float(_pickup_fx.size()) * 2.1,
		"lamp": lamp,
	})


## The rotating/bobbing motion. It is purely visual: no pickup radius, cargo
## state or objective logic reads these nodes.
func _animate_pickup_fx(now: float) -> void:
	for rec in _pickup_fx:
		# A wreck module can be replaced and freed while its record is still in
		# the list; validate before casting so a freed Variant never reaches a
		# typed assignment.
		var root = rec.get("root")
		if root == null or not is_instance_valid(root) or not root.visible:
			continue
		var indicator_node = rec.get("indicator")
		if indicator_node == null or not is_instance_valid(indicator_node):
			continue
		var indicator := indicator_node as Node3D
		if indicator == null:
			continue
		var t: float = now * 1.7 + float(rec["phase"])
		indicator.position.y = float(rec["base_y"]) + sin(t * 1.6) * 0.055
		indicator.rotation.y = t
		indicator.scale = Vector3.ONE * (1.0 + 0.035 * sin(t * 2.4))
		var lamp_node = rec.get("lamp")
		if lamp_node != null and is_instance_valid(lamp_node):
			var lamp := lamp_node as OmniLight3D
			if lamp != null:
				lamp.light_energy = PickupProps.MARKER_LAMP_ENERGY \
						* (0.82 + 0.18 * sin(t * 2.6))


## Forget a pickup record before its node is freed. Replacing a wreck module
## otherwise leaves a freed root/indicator pair in `_pickup_fx`.
func _drop_pickup_fx(root: Node) -> void:
	for i in range(_pickup_fx.size() - 1, -1, -1):
		if _pickup_fx[i].get("root") == root:
			_pickup_fx.remove_at(i)


func _anchor(anchor_name: String, fallback: Vector3) -> Vector3:
	var node := get_node_or_null("Data/Anchors/%s" % anchor_name) as Node3D
	return node.position if node != null else fallback


func _scan_data(node: Node) -> void:
	match String(node.get_meta("kind", "")):
		"hide_spot":
			hide_spots.append({
				"center": (node as Node3D).position,
				"half": node.get_meta("half"),
			})
		"ambush_spot":
			ambush_spots.append((node as Node3D).position)
		"choke":
			chokes.append({
				"center": (node as Node3D).position,
				"half": node.get_meta("half"),
				"north": node.get_meta("north"),
				"south": node.get_meta("south"),
			})
		"loud_door":
			loud_doors.append({
				"node": node,
				"open": node.get_meta("door_open"),
				"trigger": node.get_meta("door_trigger"),
				"opening": false,
				"settled": false,
				"grind_t": 0.0,
			})
		"remains":
			remains.append({
				"node": node,
				"pos": (node as Node3D).position,
				"taken": false,
			})
	for child in node.get_children():
		_scan_data(child)


func _process(delta: float) -> void:
	# One clock read for every per-frame animation below.
	var now: float = Time.get_ticks_msec() / 1000.0
	if _flicker_lamp != null and is_instance_valid(_flicker_lamp):
		_flicker_lamp.light_energy = 0.55 * (0.7 + 0.3 * sin(now * 11.0)) \
				* (0.15 if sin(now * 3.1) > 0.99 else 1.0)
	for rec in _practicals:
		var practical: OmniLight3D = rec["node"]
		if practical == null or not is_instance_valid(practical):
			continue
		var phase: float = rec["phase"]
		var wobble := 0.74 + 0.20 * sin(now * 2.1 + phase) \
				+ 0.06 * sin(now * 11.0 + phase * 2.3)
		if sin(now * 1.3 + phase) > 0.985:
			wobble *= 0.22
		practical.light_energy = float(rec["base"]) * wobble
	_animate_pickup_fx(now)
	if galley_door != null:
		var target_z := DOOR_OPEN_Z if galley_door_open else DOOR_CLOSED_Z
		var prev: Vector3 = galley_door.position
		galley_door.position.z = move_toward(galley_door.position.z, target_z,
				DOOR_SPEED * delta)
		if galley_door.position.z != prev.z:
			# Grinding metal, halfway into the frame: every half-second posts,
			# so the hosts hear the door long before you wish they had.
			_door_grind_t = _grind_scrape(_door_grind_t, delta, 0.45,
					galley_door.global_position, -6.0, 0.55, 0.45)
	if zone2_door != null:
		var target_y := ZONE2_DOOR_OPEN_Y if zone2_door_open else ZONE2_DOOR_CLOSED_Y
		var prev_y := zone2_door.position.y
		zone2_door.position.y = move_toward(zone2_door.position.y, target_y,
				ZONE2_DOOR_SPEED * delta)
		if zone2_door.position.y != prev_y:
			# The airlock only ever opens once; the scrape is the price of
			# admission, not a recurring tax on every crossing.
			_zone2_grind_t = _grind_scrape(_zone2_grind_t, delta, 0.4,
					zone2_door.global_position, -3.0, 0.5)


## The shared grind beat for every sliding door: tick the caller's own grind
## clock and, when it runs out, post exactly one scrape (and the noise event,
## when the door is loud enough to carry). Returns the new clock value, so each
## door keeps its own cadence without duplicating this block three times.
func _grind_scrape(grind_t: float, delta: float, interval: float, pos: Vector3,
		db: float, pitch: float, loud: float = 0.0, source: Node = null) -> float:
	grind_t -= delta
	if grind_t > 0.0:
		return grind_t
	Sfx.play("scrape", pos, db, pitch)
	if loud > 0.0:
		NoiseBus.emit_noise(pos, loud, source)
	return interval


## A drone died here. The ship keeps its husk; the video module survives
## inside it. Used whenever a chassis is actually caught — there is no authored
## interception, but the wreck site is a real place in the level, which is what
## makes "go back for it" an actual decision.
func spawn_wreck(pos: Vector3) -> void:
	# The hull and cable are visual-only. A corpse can land anywhere, including
	# a 1.6 m corridor; colliding wreckage there is an unpassable soft-lock.
	var hull := _box(Vector3(0.9, 0.5, 0.95), pos + Vector3(0, 0.25, 0), Mats.machine(),
			Vector3(0, 0.3, 0.35))
	hull.use_collision = false
	var cable := _box(Vector3(0.5, 0.35, 0.5), pos + Vector3(0.4, 0.18, -0.25), Mats.cable())
	cable.use_collision = false
	# Same pick-up point as the old amber box, but now a real camera model with
	# the floating marker above it. A second loss replaces the previous wreck's
	# module rather than leaving another un-pickable marker in the world.
	if _wreck_camera != null and is_instance_valid(_wreck_camera):
		_drop_pickup_fx(_wreck_camera)
		_wreck_camera.queue_free()
	var wreck_cam := Node3D.new()
	wreck_cam.name = "CameraModule"
	wreck_cam.position = pos + Vector3(0.15, 0.55, 0.05)
	add_child(wreck_cam)
	_attach_pickup_fx(wreck_cam, "camera")
	_wreck_camera = wreck_cam
	camera_module = wreck_cam
	camera_module.visible = true
	wreck_pieces = [hull, cable]


## Runtime prop helper. The static level is baked; only dynamic set dressing
## (a lost chassis) is still built here.
func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D,
		rot := Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.position = pos
	b.rotation = rot
	b.use_collision = true
	add_child(b)
	return b


## Called from main while the drone is out, and by the Collector as it walks
## its route. Each door opens once, with a heavy bang and a grinding slide;
## both post to NoiseBus. `source` tags the event so other monsters ignore a
## door opened by one of their own kind.
func service_doors(pos: Vector3, delta: float, source: Node = null) -> void:
	for d in loud_doors:
		var node: CSGBox3D = d["node"]
		if not is_instance_valid(node):
			continue
		if not d["opening"]:
			if pos.distance_to(d["trigger"]) < 1.9:
				d["opening"] = true
				d["grind_t"] = 0.0
				Sfx.play("thud", d["trigger"], 2.0)
				NoiseBus.emit_noise(d["trigger"], 1.0, source)
			continue
		if d["settled"]:
			continue
		var target: Vector3 = d["open"]
		var prev: Vector3 = node.position
		node.position = node.position.move_toward(target, LOUD_DOOR_SPEED * delta)
		if node.position != prev:
			d["grind_t"] = _grind_scrape(float(d["grind_t"]), delta, 0.30,
					d["trigger"], -2.0, 0.72, 0.5, source)
		if node.position.distance_to(target) < 0.02:
			d["settled"] = true
