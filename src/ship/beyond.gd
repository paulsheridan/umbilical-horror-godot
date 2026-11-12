extends Node3D
## The ship beyond the bay: what only drones reach. Built additive behind the
## fab bay's north wall (the bay shell stays untouched — the wall simply
## backs the vestibule).
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

var dock_pos := Vector3(-2.0, 0.32, -5.9)

# Galley door / objective constants (main drives from these).
const DOOR_CLOSED_Z := -29.2
const DOOR_OPEN_Z := -27.3
const DOOR_SPEED := 0.8    # m/s — the grind lasts ~2 s, loud the whole way
var GALLEY_DOOR_POS := Vector3(-8.65, 1.0, -29.2)
var FOOD_POS := Vector3(-18.5, 0.35, -32.7)
# The video-camera module lies on the *near* (west) lip of the wreck, not
# behind it: the spur is only 1.6 m wide and the wreck blocks the far half, so
# a rear-mounted module is outside the drone's reachable pickup envelope.
var CAMERA_POS := Vector3(6.45, 0.45, -29.75)  # video module on the wreck

# --- East annex (M6): donut + cafeteria -----------------------------------
const RING_X0 := 4.6          # junction east wall / west ring outer face
const RING_X1 := 21.0         # outer east face
const RING_Z0 := -31.4        # north ring outer face
const RING_Z1 := -16.0        # south ring outer face
const CAFE_X0 := 6.2          # cafeteria west face
const CAFE_X1 := 19.2         # cafeteria east face
const CAFE_Z0 := -28.4        # cafeteria north face
const CAFE_Z1 := -17.6        # cafeteria south face
const CAFE_DOOR_N0 := 11.0    # north arch (x span)
const CAFE_DOOR_N1 := 17.0
const CAFE_DOOR_S0 := 9.0     # south arch (x span)
const CAFE_DOOR_S1 := 15.0
const CAFE_DOOR_W0 := -25.0   # west arch (z span)
const CAFE_DOOR_W1 := -21.0
const CAFE_DOOR_E0 := -25.4   # east arch (z span)
const CAFE_DOOR_E1 := -21.0

# --- Berth wing (M6b): the crew's rooms, south of the annex ring -----------
#   link W   x 7.6..9.6,  z -16.0..-13.0  normal mouth into the south ring
#   crawl    x 12.6..13.8,z -16.0..-13.0  0.9 m service duct (drone only)
#   link E   x 16.6..18.6,z -16.0..-13.0  normal mouth (the big bodies' route)
#   hall     x 7.0..21.0, z -13.0..-10.4  berth corridor
#   cabins   z -10.4..-6.0: three berths + the Collector's ossuary
const BERTH_X0 := 7.0
const BERTH_X1 := 21.0
const BERTH_Z0 := -16.0
const BERTH_Z1 := -6.0
const BERTH_HALL_Z0 := -13.0
const BERTH_HALL_Z1 := -10.4
const CRAWL_X0 := 12.4
const CRAWL_X1 := 14.0
# The one movable deposit point for the Collector's old nest. Change this
# vector (and the matching nest geometry in _ossuary) to move the hoard.
var COLLECTOR_DEPOSIT := Vector3(19.8, 0.0, -7.2)

# --- Processor wing (M6c) --------------------------------------------------
# A long dark hall east of the berth hall, ending in the feed chamber.
const PROC_HALL_X0 := 21.0
const PROC_HALL_X1 := 28.0
const PROC_HALL_Z0 := -13.0
const PROC_HALL_Z1 := -10.4
const PROC_ROOM_X0 := 28.0
const PROC_ROOM_X1 := 33.0
const PROC_ROOM_Z0 := -15.4
const PROC_ROOM_Z1 := -8.0
# The Processor is pinned against the chamber's east wall. The pile the
# Collector now feeds sits between it and the hall mouth.
var PROCESSOR_POS := Vector3(32.1, 0.0, -11.7)
var PROCESSOR_PILE := Vector3(29.8, 0.0, -11.7)
# Where the Collector sets a carried bot down: at the pile, on the hall side,
# so the player has room to drive clear when the Processor reaches.
var PROCESSOR_DROP := Vector3(28.9, 0.32, -11.7)

var galley_door: CSGBox3D = null
var galley_door_open := false
var camera_module = null
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


## Main calls this when the drone gets close to the door plane.
func open_galley_door() -> void:
	if galley_door_open:
		return
	galley_door_open = true
	Sfx.play("thud", galley_door.global_position, -2.0)
	NoiseBus.emit_noise(galley_door.global_position, 0.55)

## The scene is the source of truth for geometry. Resolve the named anchors and
## rebuild the gameplay lists from the metadata baked onto their nodes.
func _ready() -> void:
	# Placement is editor-owned: markers override the fallbacks below.
	dock_pos = _anchor("Dock", dock_pos)
	CAMERA_POS = _anchor("CameraSite", CAMERA_POS)
	FOOD_POS = _anchor("Food", FOOD_POS)
	GALLEY_DOOR_POS = _anchor("GalleyDoorApproach", GALLEY_DOOR_POS)
	COLLECTOR_DEPOSIT = _anchor("CollectorDeposit", COLLECTOR_DEPOSIT)
	PROCESSOR_POS = _anchor("ProcessorPos", PROCESSOR_POS)
	PROCESSOR_PILE = _anchor("ProcessorPile", PROCESSOR_PILE)
	PROCESSOR_DROP = _anchor("ProcessorDrop", PROCESSOR_DROP)
	galley_door = _resolve("GalleyDoor") as CSGBox3D
	camera_module = _resolve("CameraModule")
	collector_pile = _resolve("CollectorPile") as Node3D
	processor_pile = _resolve("ProcessorPile") as Node3D
	hide_spots.clear()
	ambush_spots.clear()
	chokes.clear()
	loud_doors.clear()
	remains.clear()
	_scan_data(self)


## Resolve a named gameplay node while ignoring Marker3D anchors, which may
## share a name (the ProcessorPile anchor and the pile node are siblings in
## different containers).
func _resolve(node_name: String) -> Node:
	for node in find_children(node_name, "", true, false):
		if not node is Marker3D:
			return node
	return null


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
	var lamp := _resolve("FlickerLight") as OmniLight3D
	if lamp != null:
		var t: float = Time.get_ticks_msec() / 1000.0
		lamp.light_energy = 0.55 * (0.7 + 0.3 * sin(t * 11.0)) \
				* (0.15 if sin(t * 3.1) > 0.99 else 1.0)
	if galley_door != null:
		var target_z := DOOR_OPEN_Z if galley_door_open else DOOR_CLOSED_Z
		var prev: Vector3 = galley_door.position
		galley_door.position.z = move_toward(galley_door.position.z, target_z,
				DOOR_SPEED * delta)
		if galley_door.position.z != prev.z:
			# Grinding metal, halfway into the frame: every half-second posts,
			# so the hosts hear the door long before you wish they had.
			_door_grind_t -= delta
			if _door_grind_t <= 0.0:
				_door_grind_t = 0.45
				Sfx.play("scrape", galley_door.global_position, -6.0, 0.55)
				NoiseBus.emit_noise(galley_door.global_position, 0.45)


## A drone died here. The ship keeps its husk; the video module survives
## inside it. Used for the M4 authored loss — the wreck site is a real place
## in the level now, which is what makes "go back for it" an actual decision.
func spawn_wreck(pos: Vector3) -> void:
	# The hull and cable are visual-only. A corpse can land anywhere, including
	# a 1.6 m corridor; colliding wreckage there is an unpassable soft-lock.
	var hull := _box(Vector3(0.9, 0.5, 0.95), pos + Vector3(0, 0.25, 0), Mats.machine(),
			Vector3(0, 0.3, 0.35))
	hull.use_collision = false
	var cable := _box(Vector3(0.5, 0.35, 0.5), pos + Vector3(0.4, 0.18, -0.25), Mats.cable())
	cable.use_collision = false
	camera_module = _box(Vector3(0.28, 0.16, 0.22),
			pos + Vector3(0.15, 0.55, 0.05), Mats.amber())
	camera_module.use_collision = false
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
		node.position = node.position.move_toward(target, 1.7 * delta)
		if node.position != prev:
			d["grind_t"] = float(d["grind_t"]) - delta
			if float(d["grind_t"]) <= 0.0:
				d["grind_t"] = 0.30
				Sfx.play("scrape", d["trigger"], -2.0, 0.72)
				NoiseBus.emit_noise(d["trigger"], 0.5, source)
		if node.position.distance_to(target) < 0.02:
			d["settled"] = true
