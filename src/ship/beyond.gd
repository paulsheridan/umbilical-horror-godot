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
const GALLEY_DOOR_POS := Vector3(-8.65, 1.0, -29.2)
const FOOD_POS := Vector3(-18.5, 0.35, -32.7)
# The video-camera module lies on the *near* (west) lip of the wreck, not
# behind it: the spur is only 1.6 m wide and the wreck blocks the far half, so
# a rear-mounted module is outside the drone's reachable pickup envelope.
const CAMERA_POS := Vector3(6.45, 0.45, -29.75)  # video module on the wreck

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
const COLLECTOR_DEPOSIT := Vector3(19.8, 0.0, -7.2)

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
const PROCESSOR_POS := Vector3(32.1, 0.0, -11.7)
const PROCESSOR_PILE := Vector3(29.8, 0.0, -11.7)
# Where the Collector sets a carried bot down: at the pile, on the hall side,
# so the player has room to drive clear when the Processor reaches.
const PROCESSOR_DROP := Vector3(28.9, 0.32, -11.7)

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


func build() -> void:
	_flat_floor()
	_vestibule()
	_leg_a()
	_bend_b()
	_leg_c()
	_junction()
	_spur()
	_east_annex()
	_berth_wing()
	_processor_wing()
	_galley_stub()
	_galley()
	_dressing()
	_ambush_spots()


func _ambush_spots() -> void:
	# Corners and junction mouths. The stalker folds into these when it wants
	# to wait at drone/face height for a drive-by.
	ambush_spots = [
		Vector3(-4.0, 0.2, -32.0),    # junction NW
		Vector3(4.0, 0.2, -32.0),     # junction NE
		Vector3(3.9, 0.2, -26.2),     # junction SE, near the east mouth
		Vector3(6.8, 0.2, -27.8),     # cafeteria NW
		Vector3(18.6, 0.2, -27.8),    # cafeteria NE
		Vector3(6.8, 0.2, -18.2),     # cafeteria SW
		Vector3(18.6, 0.2, -18.2),    # cafeteria SE
		Vector3(20.1, 0.2, -29.7),    # ring NE
		Vector3(20.1, 0.2, -16.8),    # ring SE
		Vector3(5.4, 0.2, -16.8),     # ring SW
		Vector3(5.4, 0.2, -29.6),     # spur mouth / junction approach
	]


## One continuous collision plane under the whole drone-space. (Visual floor
## slabs stay, but with use_collision = false.) Per-compartment floor
## colliders meeting edge-to-edge were catching sled-like bodies on the
## seams; a single slab cannot have seams. For testing, the whole ship is
## now a perfectly flat floor at y = 0.
func _flat_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(56.0, 0.5, 31.0)   # x -21..35, z -35.9..-4.9
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(7.0, -0.25, -20.4)
	add_child(body)


## A low work table. Its top clears the drone's camera mast (and hides it) but
## is too low for the tall stalker's body. Its footprint becomes a hide spot
## the stalker's sight respects.
func _low_table(center: Vector3, w: float, d: float) -> void:
	var top := _box(Vector3(w, 0.12, d), center + Vector3(0, 1.40, 0), Mats.machine())
	top.use_collision = true
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.09, 1.40, 0.09),
					center + Vector3(sx * (w * 0.5 - 0.12), 0.70, sz * (d * 0.5 - 0.12)),
					Mats.hull())
	# A dim amber strip underneath marks the hiding hole in the dark.
	var strip := _box(Vector3(w * 0.52, 0.03, 0.05),
			center + Vector3(0, 1.28, -d * 0.5 + 0.06), Mats.amber())
	strip.use_collision = false
	var tray := _box(Vector3(0.5, 0.05, 0.34),
			center + Vector3(w * 0.18, 1.47, 0.1), Mats.hull())
	tray.use_collision = false
	hide_spots.append({
		"center": center,
		"half": Vector2(w * 0.5 - 0.25, d * 0.5 - 0.25),
	})


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.material = mat
	b.position = pos
	b.rotation = rot
	b.use_collision = true
	add_child(b)
	return b


func _cyl(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = height
	c.material = mat
	c.position = pos
	c.rotation = rot
	c.use_collision = true
	add_child(c)
	return c


func _light(pos: Vector3, color: Color, energy: float, range: float, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.shadow_enabled = false
	add_child(l)
	if flicker:
		set_meta("flicker", l)
	return l


func _process(delta: float) -> void:
	var l = get_meta("flicker", null) if has_meta("flicker") else null
	if l != null:
		var t: float = Time.get_ticks_msec() / 1000.0
		l.light_energy = 0.55 * (0.7 + 0.3 * sin(t * 11.0)) * (0.15 if sin(t * 3.1) > 0.99 else 1.0)
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


## Encloses a volume: floor, ceiling, four walls. Faces marked open are left
## to be closed by the run on the other side (or by explicit segments).
## Floors/ceilings butt-joint exactly (no overlap, no dy offsets): any lip
## between compartments becomes a wall to a box-shaped body — the drone and
## hosts were getting snagged on 1 cm seams. Coped floor CONTACT only exists
## inside a single run; crossings cross exactly coplanar slabs.
func _run(x0: float, x1: float, z0: float, z1: float, h: float,
		m: StandardMaterial3D, open_n := false, open_s := false,
		open_w := false, open_e := false) -> void:
	var w := x1 - x0
	var d := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Visual floor only — the single flat collider in _flat_floor() is the
	# actual walking/driving surface.
	var floor_slab := _box(Vector3(w, 0.3, d), Vector3(cx, -0.15, cz), Mats.deck())
	floor_slab.use_collision = false
	_box(Vector3(w, 0.3, d), Vector3(cx, h + 0.15, cz), Mats.ceil())
	if not open_w:
		_box(Vector3(0.4, h, d), Vector3(x0 - 0.2, h * 0.5, cz), m)
	if not open_e:
		_box(Vector3(0.4, h, d), Vector3(x1 + 0.2, h * 0.5, cz), m)
	if not open_n:
		_box(Vector3(w, h, 0.4), Vector3(cx, h * 0.5, z0 - 0.2), m)
	if not open_s:
		_box(Vector3(w, h, 0.4), Vector3(cx, h * 0.5, z1 + 0.2), m)


func _vestibule() -> void:
	# South face closed by the fab bay wall itself (z -5.4..-5.0).
	_run(-3.4, -1.2, -6.4, -5.4, 3.0, Mats.wall(), true, true, false, false)


func _leg_a() -> void:
	# North run; open both ends (vestibule on the south, bend on the north).
	_run(-3.4, -1.2, -14.4, -6.4, 3.0, Mats.wall(), true, true, false, false)
	# Failing wall lamp mid-run (pitched ambience).
	_light(Vector3(-3.2, 2.5, -10.5), Color(1.0, 0.8, 0.55), 0.5, 5.0, true)


func _bend_b() -> void:
	# East jog. The west end is a natural nook before leg C's mouth.
	_run(-3.4, 1.4, -16.4, -14.4, 3.0, Mats.wall(), true, true, false, false)
	# North face: wall wherever leg C's mouth (x -1.4..1.0) is not.
	_box(Vector3(2.4, 3.0, 0.4), Vector3(-2.6, 1.5, -16.6), Mats.wall())   # nook
	_box(Vector3(0.4, 3.0, 0.4), Vector3(1.2, 1.5, -16.6), Mats.wall())    # east sliver
	# South face: wall east of leg A's east wall (x -1.2..1.4 remains).
	_box(Vector3(2.2, 3.0, 0.4), Vector3(0.3, 1.5, -14.2), Mats.wall())
	_light(Vector3(0.6, 2.6, -15.3), Color(0.7, 0.8, 1.0), 0.32, 4.0)


func _leg_c() -> void:
	_run(-1.4, 1.0, -25.6, -16.4, 3.0, Mats.wall(), true, true, false, false)
	# Cable run pinned along the west wall foot. Visual only — see _dressing():
	# ankle-height dressing must never have collision.
	var wall_cable := _cyl(0.05, 9.0, Vector3(-1.15, 0.07, -21.0), Mats.cable(), Vector3(0, 0, PI * 0.5))
	wall_cable.use_collision = false


func _junction() -> void:
	# Big dark room. Open on: south (leg C mouth), east (spur), west (stub).
	_run(-4.6, 4.6, -32.6, -25.6, 3.2, Mats.wall(), false, true, true, true)
	# South face segments (either side of leg C's mouth) + lintel mouth cap.
	_box(Vector3(3.6, 3.2, 0.4), Vector3(-3.2, 1.6, -25.4), Mats.wall())
	_box(Vector3(3.6, 3.2, 0.4), Vector3(2.8, 1.6, -25.4), Mats.wall())
	_box(Vector3(2.4, 0.18, 0.4), Vector3(-0.2, 3.11, -25.4), Mats.wall())
	# East face: open from z -31.4 to -25.6. That is two wide mouths into
	# the east annex: the old spur (north ring) and the west ring. A short
	# hull column at the corner keeps them reading as two doorways instead
	# of one enormous hole.
	_box(Vector3(0.4, 3.2, 1.4), Vector3(4.8, 1.6, -32.1), Mats.wall())
	_box(Vector3(0.4, 3.2, 0.4), Vector3(4.4, 1.6, -28.4), Mats.hull())
	# West face segments (opening z -30.0..-28.4 = the galley stub).
	_box(Vector3(0.4, 3.2, 2.8), Vector3(-4.8, 1.6, -31.4), Mats.wall())
	_box(Vector3(0.4, 3.2, 3.2), Vector3(-4.8, 1.6, -26.8), Mats.wall())

	_box(Vector3(0.6, 3.2, 0.6), Vector3(-2.5, 1.6, -30.6), Mats.hull())
	_box(Vector3(0.6, 3.2, 0.6), Vector3(2.5, 1.6, -31.2), Mats.hull())
	_box(Vector3(0.85, 0.5, 0.85), Vector3(3.0, 0.25, -31.4), Mats.crate(),
			Vector3(0, 0, 0.3))
	# Low work tables: the drone fits under, the stalker does not. These are
	# the junction's hiding spots during the first encounter.
	_low_table(Vector3(-3.3, 0.0, -26.6), 2.6, 1.6)
	_low_table(Vector3(0.0, 0.0, -31.2), 2.6, 1.6)
	# The dead strip fixture: barely there, flickering. It casts shadows so
	# the stalker's long silhouette can move across the junction walls.
	var junction_lamp := _light(Vector3(0.0, 3.0, -29.0), Color(1.0, 0.75, 0.5), 0.55, 7.0, true)
	junction_lamp.shadow_enabled = true


func _spur() -> void:
	# The old dead end is now the west end of the north ring. Open east into
	# the ring and south into the west ring; only the north face is solid.
	# The wreck is shifted to the north side so a full-width lane remains for
	# the drone (and a patroller) to pass the salvage on the way around.
	_run(4.6, 9.0, -31.4, -28.4, 3.0, Mats.wall(), false, true, true, true)
	_box(Vector3(0.8, 0.7, 0.8), Vector3(8.4, 0.35, -30.5), Mats.crate(), Vector3(0, 0.4, 0))
	_wreck()


func _wreck() -> void:
	# The wrecked maintenance drone — a machine like the player's own, dead on
	# the floor of the spur, its video-camera module still intact. This is the
	# salvage: the live-video upgrade comes off a corpse (disabled for the
	# first drone iteration, but it is the module the story sends you after).
	# It sits against the north wall; the camera rests on its south lip, in
	# the lane the drone can actually reach now that the spur is a through-route.
	_box(Vector3(0.9, 0.5, 0.95), Vector3(7.15, 0.25, -30.35), Mats.machine(),
			Vector3(0, 0, 0.35))
	_box(Vector3(0.5, 0.35, 0.5), Vector3(6.95, 0.18, -30.55), Mats.cable())
	# The wreck's prize: the video camera, amber-cased and dimly hopeful.
	camera_module = _box(Vector3(0.28, 0.16, 0.22), CAMERA_POS, Mats.amber())
	camera_module.use_collision = false   # pickups must not block the drone


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


## The east annex: a donut service corridor around a gutted cafeteria. This
## is the "more ship" the survivors never mapped — long enough that a host
## can be somewhere else, and wide enough that the drone can actually run.
func _east_annex() -> void:
	# Floors/ceilings only. The north ring extension continues the spur east;
	# the big annex slab covers the west ring, the cafeteria and the south and
	# east rings in one seam-free visual surface.
	_run(9.0, RING_X1, RING_Z0, CAFE_Z0, 3.0, Mats.wall(), true, true, true, true)
	_run(RING_X0, RING_X1, CAFE_Z0, RING_Z1, 3.0, Mats.wall(), true, true, true, true)

	# Outer shell. The west wall only starts south of the two junction mouths.
	_box(Vector3(RING_X1 - 9.0, 3.0, 0.4),
			Vector3((9.0 + RING_X1) * 0.5, 1.5, RING_Z0 - 0.2), Mats.wall())
	_box(Vector3(0.4, 3.0, RING_Z1 - RING_Z0),
			Vector3(RING_X1 + 0.2, 1.5, (RING_Z0 + RING_Z1) * 0.5), Mats.wall())
	_box(Vector3(0.4, 3.0, RING_Z1 - RING_Z0),
			Vector3(RING_X1 + 0.2, 1.5, (RING_Z0 + RING_Z1) * 0.5), Mats.wall())
	# South shell, split around the berth wing's three openings: two normal
	# link mouths (x 7.6..9.6 and 16.6..18.6) and the low service crawl.
	for span in [[RING_X0, 7.6], [9.6, CRAWL_X0], [CRAWL_X1, 16.6], [18.6, RING_X1]]:
		var sx0: float = span[0]
		var sx1: float = span[1]
		_box(Vector3(sx1 - sx0, 3.0, 0.4),
				Vector3((sx0 + sx1) * 0.5, 1.5, RING_Z1 + 0.2), Mats.wall())
	# The crawl's header: the opening is only 1.0 m tall.
	_box(Vector3(CRAWL_X1 - CRAWL_X0, 2.0, 0.4),
			Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, 2.0, RING_Z1 + 0.2), Mats.wall())
	_box(Vector3(0.4, 3.0, RING_Z1 + 25.6),
			Vector3(RING_X0 - 0.2, 1.5, (-25.6 + RING_Z1) * 0.5), Mats.wall())

	# Cafeteria walls: four arches, one per side of the donut. Walls sit just
	# inside the cafeteria so the ring corridors keep their full width.
	# North wall (faces the north ring).
	_box(Vector3(CAFE_DOOR_N0 - CAFE_X0, 3.0, 0.4),
			Vector3((CAFE_X0 + CAFE_DOOR_N0) * 0.5, 1.5, CAFE_Z0 + 0.2), Mats.wall())
	_box(Vector3(CAFE_X1 - CAFE_DOOR_N1, 3.0, 0.4),
			Vector3((CAFE_DOOR_N1 + CAFE_X1) * 0.5, 1.5, CAFE_Z0 + 0.2), Mats.wall())
	# South wall (faces the south ring).
	_box(Vector3(CAFE_DOOR_S0 - CAFE_X0, 3.0, 0.4),
			Vector3((CAFE_X0 + CAFE_DOOR_S0) * 0.5, 1.5, CAFE_Z1 - 0.2), Mats.wall())
	_box(Vector3(CAFE_X1 - CAFE_DOOR_S1, 3.0, 0.4),
			Vector3((CAFE_DOOR_S1 + CAFE_X1) * 0.5, 1.5, CAFE_Z1 - 0.2), Mats.wall())
	# West wall (faces the west ring).
	_box(Vector3(0.4, 3.0, CAFE_DOOR_W0 - CAFE_Z0),
			Vector3(CAFE_X0 + 0.2, 1.5, (CAFE_Z0 + CAFE_DOOR_W0) * 0.5), Mats.wall())
	_box(Vector3(0.4, 3.0, CAFE_Z1 - CAFE_DOOR_W1),
			Vector3(CAFE_X0 + 0.2, 1.5, (CAFE_DOOR_W1 + CAFE_Z1) * 0.5), Mats.wall())
	# East wall (faces the east ring).
	_box(Vector3(0.4, 3.0, CAFE_DOOR_E0 - CAFE_Z0),
			Vector3(CAFE_X1 - 0.2, 1.5, (CAFE_Z0 + CAFE_DOOR_E0) * 0.5), Mats.wall())
	_box(Vector3(0.4, 3.0, CAFE_Z1 - CAFE_DOOR_E1),
			Vector3(CAFE_X1 - 0.2, 1.5, (CAFE_DOOR_E1 + CAFE_Z1) * 0.5), Mats.wall())

	# Dead serving line along the north wall, clear of the north arch.
	_box(Vector3(3.4, 0.9, 0.7), Vector3(8.6, 0.45, -27.75), Mats.machine())
	_box(Vector3(3.8, 0.08, 0.9), Vector3(8.6, 0.92, -27.75), Mats.hull())
	_box(Vector3(2.0, 0.05, 0.02), Vector3(8.6, 0.72, -27.39), Mats.amber())

	# Two long mess tables with benches. Solid enough to stop a crawler, but
	# the west half of the room is kept open for a chase lane.
	for z in [-25.5, -22.0]:
		_box(Vector3(7.0, 0.72, 1.2), Vector3(12.5, 0.36, z), Mats.hull())
		_box(Vector3(7.2, 0.08, 1.4), Vector3(12.5, 0.76, z), Mats.machine())
		_box(Vector3(7.2, 0.42, 0.4), Vector3(12.5, 0.21, z - 0.9), Mats.machine())
		_box(Vector3(7.2, 0.42, 0.4), Vector3(12.5, 0.21, z + 0.9), Mats.machine())
		for x in [10.0, 12.5, 15.0]:
			var tray := _box(Vector3(0.5, 0.04, 0.34), Vector3(x, 0.82, z), Mats.hull())
			tray.use_collision = false
	# A table on its side in the south-west open corner: cover, not furniture.
	_box(Vector3(2.0, 0.12, 1.0), Vector3(8.2, 0.62, -19.4), Mats.hull(),
			Vector3(0, 0.45, 1.35))
	# A low work table in the south-east corner: another drone-sized hiding
	# spot, away from the stalker's patrol lane.
	_low_table(Vector3(16.0, 0.0, -19.2), 2.4, 1.4)
	# Cables and a dead trolley, visual only so nothing catches a track.
	var c1 := _cyl(0.05, 8.0, Vector3(11.0, 0.07, -28.0), Mats.cable(),
			Vector3(0, 0, PI * 0.5))
	c1.use_collision = false
	var c2 := _cyl(0.05, 9.0, Vector3(6.4, 0.07, -22.0), Mats.cable(),
			Vector3(PI * 0.5, 0, 0))
	c2.use_collision = false

	# Sparse practicals. The cafeteria's one flicker is the room's heartbeat.
	_light(Vector3(12.0, 2.8, -26.0), Color(1.0, 0.78, 0.5), 0.55, 9.0, true)
	_light(Vector3(9.0, 2.8, -20.5), Color(0.7, 0.8, 1.0), 0.26, 6.0)
	_light(Vector3(18.0, 2.8, -20.0), Color(0.9, 0.15, 0.1), 0.28, 5.0)
	_light(Vector3(14.0, 2.8, -29.7), Color(0.8, 0.75, 0.6), 0.26, 5.0)
	_light(Vector3(20.1, 2.8, -22.5), Color(0.55, 0.7, 1.0), 0.24, 5.0)

	# Ceiling runs: pipes along the ring, so the donut reads as machinery.
	for i in 2:
		_cyl(0.07, 13.0, Vector3(20.0 + 0.18 * i, 2.82, -23.7), Mats.machine(),
				Vector3(PI * 0.5, 0, 0))
	var pipe := _cyl(0.08, 14.0, Vector3(12.5, 2.85, -29.6), Mats.machine(),
			Vector3(0, 0, PI * 0.5))
	pipe.use_collision = false


## The berth wing: the crew's rooms behind the south ring. Three small cabins
## with loud sliding doors and lofted bunks to hide under, a low service crawl
## only the drone fits through, a fallen locker, and the Collector's ossuary.
## The tall bodies must take the east link around the crawl (see `chokes`).
func _berth_wing() -> void:
	# Shell: visual floor/ceiling, west/south walls, open to the ring and to
	# the Processor hall in the east.
	_run(BERTH_X0, BERTH_X1, BERTH_Z0, BERTH_Z1, 3.0, Mats.wall(),
			true, false, false, true)
	# East wall, broken only by the hall mouth (the full hall width).
	_box(Vector3(0.4, 3.0, 3.0), Vector3(BERTH_X1 + 0.2, 1.5, -14.5), Mats.wall())
	_box(Vector3(0.4, 3.0, 4.4), Vector3(BERTH_X1 + 0.2, 1.5, -8.2), Mats.wall())

	# Link walls. The west link also carries the fallen locker; the east link
	# is the only clean route for a Stalker-sized body.
	for x in [7.6, 9.6, 16.6, 18.6]:
		_box(Vector3(0.4, 3.0, 3.0), Vector3(x, 1.5, -14.5), Mats.wall())

	# Hall north wall, broken by the two link mouths and the low crawl.
	for span in [[BERTH_X0, 7.6], [9.6, CRAWL_X0], [CRAWL_X1, 16.6], [18.6, BERTH_X1]]:
		var sx0: float = span[0]
		var sx1: float = span[1]
		_box(Vector3(sx1 - sx0, 3.0, 0.4),
				Vector3((sx0 + sx1) * 0.5, 1.5, BERTH_HALL_Z0 - 0.2), Mats.wall())
	_box(Vector3(CRAWL_X1 - CRAWL_X0, 2.0, 0.4),
			Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, 2.0, BERTH_HALL_Z0 - 0.2),
			Mats.wall())
	# The crawl's sides and low ceiling: 1.0 m of headroom for the whole run.
	for x in [CRAWL_X0, CRAWL_X1]:
		_box(Vector3(0.12, 1.0, 3.0), Vector3(x, 0.50, -14.5), Mats.hull())
	var crawl_top := _box(Vector3(CRAWL_X1 - CRAWL_X0 + 0.24, 0.12, 3.0),
			Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, 1.06, -14.5), Mats.hull())
	crawl_top.use_collision = true
	# A dim amber guide line on the deck leads the drone into the crawl. It
	# sits on the floor (not across the mouth) so it reads as a route, not a
	# barrier to duck under.
	for gz in [-15.85, -13.15]:
		var crawl_glow := _box(Vector3(CRAWL_X1 - CRAWL_X0 - 0.25, 0.02, 0.06),
				Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, 0.025, gz), Mats.amber())
		crawl_glow.use_collision = false

	# Cabin party walls (0.8 m thick service spines between rooms).
	for x in [10.8, 14.6, 18.4]:
		_box(Vector3(0.8, 3.0, 4.4), Vector3(x, 1.5, -8.2), Mats.wall())

	# Hall south wall / cabin fronts. Four 1.5 m doorways.
	var fronts := [
		[7.0, 8.15], [9.65, 11.95], [13.45, 15.75], [17.25, 19.15], [20.65, 21.0],
	]
	for span in fronts:
		var fx0: float = span[0]
		var fx1: float = span[1]
		_box(Vector3(fx1 - fx0, 3.0, 0.4),
				Vector3((fx0 + fx1) * 0.5, 1.5, BERTH_HALL_Z1 - 0.2), Mats.wall())
	for dx in [8.9, 12.7, 16.5, 19.9]:
		_box(Vector3(1.5, 0.9, 0.4), Vector3(dx, 2.55, BERTH_HALL_Z1 - 0.2),
				Mats.wall())
		_loud_door(Vector3(dx, 0.0, BERTH_HALL_Z1 - 0.34))

	# Cabins: lofted bunks (hide under), each with a little dead furniture.
	_bunk(Vector3(8.7, 0.0, -7.4), 1.5, 2.1)
	_bunk(Vector3(12.7, 0.0, -7.4), 1.5, 2.1)
	_bunk(Vector3(16.5, 0.0, -7.4), 1.5, 2.1)
	for cx in [8.7, 12.7, 16.5]:
		var shelf := _box(Vector3(0.9, 0.55, 0.35), Vector3(cx + 0.9, 0.90, -6.25),
				Mats.machine())
		shelf.use_collision = false
	# A dead cabin lamp in each berth.
	_light(Vector3(8.7, 2.7, -8.0), Color(0.8, 0.85, 1.0), 0.24, 4.0)
	_light(Vector3(12.7, 2.7, -8.0), Color(0.9, 0.7, 0.45), 0.20, 4.0, true)
	_light(Vector3(16.5, 2.7, -8.0), Color(0.8, 0.85, 1.0), 0.18, 4.0)

	# The ossuary: the Collector's nest at the east end of the wing.
	_ossuary()
	# A fallen locker leaned across the west link: a drone can slip under,
	# the tall bodies cannot. Another reason the east link is their route.
	_fallen_locker(Vector3(8.6, 0.0, -14.5))
	# Hall practicals.
	_light(Vector3(13.2, 2.8, -11.7), Color(1.0, 0.78, 0.5), 0.38, 6.0, true)
	_light(Vector3(19.8, 2.8, -12.0), Color(0.8, 0.3, 0.2), 0.26, 5.0)

	# Scattered crew remains for the Collector, laid along its walking loop.
	# Every point is east of the junction: the start rooms stay empty of
	# scavenged bodies so the only traffic there is the one patroller.
	for p in [
		Vector3(19.5, 0.0, -11.7),   # outside the ossuary
		Vector3(17.4, 0.0, -14.8),   # east link
		Vector3(14.0, 0.0, -16.8),   # south ring
		Vector3(8.5, 0.0, -16.8),    # south ring west
		Vector3(5.4, 0.0, -20.0),    # west ring
		Vector3(5.4, 0.0, -23.0),    # west ring
		Vector3(5.4, 0.0, -26.0),    # west ring north
		Vector3(5.4, 0.0, -29.6),    # NW ring corner
		Vector3(9.5, 0.0, -29.6),    # north ring
		Vector3(15.0, 0.0, -29.6),   # north ring
		Vector3(20.0, 0.0, -26.0),   # east ring north
		Vector3(20.0, 0.0, -24.0),   # east ring
	]:
		_remains(p)

	# Chokes: the objective low crawl and the fallen-locker link. Anything
	# taller than a drone must route around through the east link. Each is a
	# thin plane (the barrier), not the tunnel's whole depth, so once the
	# stalker is around it the direct pursuit is clear.
	chokes = [
		{
			"center": Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, 0.0, -15.8),
			"half": Vector2((CRAWL_X1 - CRAWL_X0) * 0.5 + 0.15, 0.35),
			"north": Vector3(17.6, 0.0, -16.8),
			"south": Vector3(17.6, 0.0, -11.8),
		},
		{
			"center": Vector3(8.6, 0.0, -14.5),
			"half": Vector2(1.1, 0.6),
			"north": Vector3(17.6, 0.0, -16.8),
			"south": Vector3(17.6, 0.0, -11.8),
		},
	]


## A sliding cabin door. It is a real panel, so it blocks until it has opened;
## opening is loud enough to carry through the annex (a NoiseBus event, not an
## alarm klaxon).
func _loud_door(center: Vector3) -> void:
	var panel := _box(Vector3(1.5, 2.1, 0.14), center + Vector3(0, 1.05, 0),
			Mats.machine())
	var latch := _box(Vector3(0.06, 0.10, 0.03),
			center + Vector3(0.58, 1.02, -0.09), Mats.amber())
	latch.use_collision = false
	loud_doors.append({
		"node": panel,
		"open": panel.position + Vector3(1.62, 0, 0),
		"trigger": center + Vector3(0, 0.6, -0.55),
		"opening": false,
		"settled": false,
		"grind_t": 0.0,
	})


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


## A lofted bunk: mattress above head height, open underneath. The drone can
## drive beneath it; its footprint is a true sight-hide spot.
func _bunk(center: Vector3, w: float, d: float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.10, 1.02, 0.10),
					center + Vector3(sx * (w * 0.5 - 0.10), 0.51, sz * (d * 0.5 - 0.10)),
					Mats.machine())
	_box(Vector3(w, 0.12, d), center + Vector3(0, 1.08, 0), Mats.machine())
	_box(Vector3(w - 0.12, 0.18, d - 0.12), center + Vector3(0, 1.19, 0),
			Mats.paper())
	var pillow := _box(Vector3(0.46, 0.14, 0.30),
			center + Vector3(0, 1.33, -d * 0.5 + 0.38), Mats.paper())
	pillow.use_collision = false
	# The under-bunk tell: a faint amber line, like the low tables.
	var strip := _box(Vector3(w * 0.45, 0.03, 0.05),
			center + Vector3(0, 1.00, -d * 0.5 + 0.05), Mats.amber())
	strip.use_collision = false
	hide_spots.append({
		"center": center,
		"half": Vector2(w * 0.5 - 0.22, d * 0.5 - 0.22),
	})


## A locker torn off its mounts and leaned across the link. The body hangs at
## chest height: the drone passes beneath, a person-sized body does not.
func _fallen_locker(center: Vector3) -> void:
	var tilt := 0.30
	var body := _box(Vector3(1.9, 0.55, 0.62), center + Vector3(0, 1.36, 0),
			Mats.machine(), Vector3(0, 0, tilt))
	var face := _box(Vector3(1.72, 0.48, 0.06),
			center + Vector3(0.04, 1.36, -0.33), Mats.hull(),
			Vector3(0, 0, tilt))
	face.use_collision = false
	# Vents, not a centred stripe: a lit stripe across the face read as a sign.
	for vx in [-0.38, 0.38]:
		var vent := _box(Vector3(0.5, 0.05, 0.02),
				center + Vector3(vx, 1.36 + vx * sin(tilt), -0.365), Mats.amber(),
				Vector3(0, 0, tilt))
		vent.use_collision = false
	# The high end rests on torn mounts at the link wall; the low end's door
	# hangs open. Visual only, so nothing can snag the drone underneath.
	for sz in [-0.30, 0.30]:
		var bracket := _box(Vector3(0.16, 0.10, 0.10),
				center + Vector3(0.90, 1.74, sz), Mats.hull())
		bracket.use_collision = false
	var door := _box(Vector3(0.06, 0.70, 0.55),
			center + Vector3(-0.95, 1.05, -0.28), Mats.hull(),
			Vector3(0, 0, -0.22))
	door.use_collision = false
	# Spilled locker contents: visual only, no snagging.
	for i in 3:
		var scrap := _box(Vector3(0.22, 0.04, 0.16),
				center + Vector3(-0.55 + 0.5 * i, 0.03, 0.5 + 0.12 * i),
				Mats.crate(), Vector3(0, 0.5 * i, 0))
		scrap.use_collision = false


## The Collector's hoard room. The pile node is the single movable deposit
## point (`COLLECTOR_DEPOSIT`); the Collector only needs the node, not the room.
func _ossuary() -> void:
	# The one movable deposit point drives the room dressing too.
	var px: float = COLLECTOR_DEPOSIT.x
	var pz: float = COLLECTOR_DEPOSIT.z
	var warm := _box(Vector3(2.0, 0.10, 1.6),
			Vector3(px, 0.05, pz + 0.35), Mats.crate())
	warm.use_collision = false
	var pallet := _box(Vector3(1.15, 0.08, 0.85),
			Vector3(px, 0.11, pz + 0.05), Mats.hull())
	pallet.use_collision = false
	collector_pile = Node3D.new()
	collector_pile.position = COLLECTOR_DEPOSIT
	add_child(collector_pile)
	# A starter heap: the parts it brought before you ever saw it. Pale bone
	# stacked pale-side-up against the dark bedding is the read from the door.
	for i in 7:
		var bone := CSGBox3D.new()
		var a := 0.9 * float(i)
		var r := 0.10 + 0.06 * float(i)
		bone.size = Vector3(0.30 + 0.04 * float(i), 0.08 + 0.02 * float(i % 2), 0.10)
		bone.position = Vector3(cos(a) * r, 0.17 + 0.055 * float(i), sin(a) * r * 0.7)
		bone.rotation = Vector3(0, a, 0.25 * sin(a))
		bone.material = Mats.bone()
		bone.use_collision = false
		collector_pile.add_child(bone)
	# A skull on top and a few bones leaning against the wall give the heap a
	# silhouette from the hallway; flat parts alone read as plates.
	var skull := CSGSphere3D.new()
	skull.radius = 0.105
	skull.scale = Vector3(0.9, 1.15, 1.0)
	skull.position = Vector3(0.10, 0.60, 0.02)
	skull.material = Mats.bone()
	skull.use_collision = false
	collector_pile.add_child(skull)
	for i in 3:
		var lean := CSGBox3D.new()
		lean.size = Vector3(0.055, 0.46, 0.055)
		lean.position = Vector3(-0.34 + 0.30 * float(i), 0.36, -0.26 + 0.05 * float(i))
		lean.rotation = Vector3(-0.72, 0.4 * float(i), 0.18 * float(i))
		lean.material = Mats.bone()
		lean.use_collision = false
		collector_pile.add_child(lean)
	# A guttering lamp low over the pile, so the hoard reads before the ceiling.
	var nest_lamp := _light(Vector3(px + 0.2, 1.05, pz + 0.1),
			Color(1.0, 0.55, 0.26), 0.55, 2.8)
	nest_lamp.shadow_enabled = false
	# Loose parts around the nest that it has not stacked yet.
	for i in 4:
		var loose := CSGBox3D.new()
		loose.size = Vector3(0.22, 0.06, 0.09)
		var a2 := 1.7 * float(i)
		loose.position = Vector3(px + cos(a2) * 0.8, 0.05,
				pz + 0.95 + sin(a2) * 0.45)
		loose.rotation = Vector3(0, a2, 0)
		loose.material = Mats.bone()
		loose.use_collision = false
		add_child(loose)
	var glow := _light(Vector3(px, 2.5, pz - 0.4), Color(0.9, 0.28, 0.12), 0.35, 4.0)
	glow.shadow_enabled = true
	# A bone chime above the nest, so the room reads before you see the pile.
	for i in 5:
		var chime := CSGCylinder3D.new()
		chime.radius = 0.015
		chime.height = 0.18 + 0.07 * i
		chime.position = Vector3(px - 0.5 + 0.25 * i, 2.55 - 0.09 * i, pz - 0.7)
		chime.material = Mats.bone()
		chime.use_collision = false
		add_child(chime)


## The Processor wing: a long, nearly lightless service hall off the berth
## hall's east side, ending in the feed chamber. The hall is deliberately
## empty and narrow: the only thing at the end is the mouth, and the only
## thing on the floor is what the Collector has already brought it.
func _processor_wing() -> void:
	# Hall: north/south walls only; both ends open into the berth and chamber.
	_run(PROC_HALL_X0, PROC_HALL_X1, PROC_HALL_Z0, PROC_HALL_Z1, 3.0,
			Mats.wall(), false, false, true, true)
	# Chamber: open only where the hall meets it. The west wall is closed in
	# two segments so the mouth is a real doorway, not a missing wall.
	_run(PROC_ROOM_X0, PROC_ROOM_X1, PROC_ROOM_Z0, PROC_ROOM_Z1, 3.4,
			Mats.wall(), false, false, true, false)
	var west := PROC_ROOM_X0 - 0.2
	_box(Vector3(0.4, 3.4, PROC_HALL_Z0 - PROC_ROOM_Z0),
			Vector3(west, 1.7, (PROC_ROOM_Z0 + PROC_HALL_Z0) * 0.5), Mats.wall())
	_box(Vector3(0.4, 3.4, PROC_ROOM_Z1 - PROC_HALL_Z1),
			Vector3(west, 1.7, (PROC_HALL_Z1 + PROC_ROOM_Z1) * 0.5), Mats.wall())

	# The hall's one working fixture is at the far end and mostly dead. The
	# drone's lamp is the light you actually drive by.
	_light(Vector3(27.2, 2.7, -11.7), Color(0.9, 0.28, 0.16), 0.30, 4.2, true)
	_light(Vector3(23.5, 2.75, -11.7), Color(0.55, 0.62, 0.75), 0.10, 3.0)
	# A low amber guide line on the deck: the Collector's route to the pile.
	for gx in [22.4, 24.0, 25.6, 27.2]:
		var guide := _box(Vector3(0.7, 0.02, 0.05),
				Vector3(gx, 0.025, -11.7), Mats.amber())
		guide.use_collision = false
	# Ceiling service run, visual only.
	var pipe := _cyl(0.08, 6.4, Vector3(24.5, 2.84, -12.3), Mats.machine(),
			Vector3(0, 0, PI * 0.5))
	pipe.use_collision = false

	# The feeding pile: a pallet in front of the Processor with a starter heap
	# of what the Collector brought before the player ever found the room.
	var px: float = PROCESSOR_PILE.x
	var pz: float = PROCESSOR_PILE.z
	var plate := _box(Vector3(1.5, 0.08, 1.1), Vector3(px, 0.05, pz), Mats.hull())
	plate.use_collision = false
	processor_pile = Node3D.new()
	processor_pile.position = PROCESSOR_PILE
	add_child(processor_pile)
	for i in 9:
		var bone := CSGBox3D.new()
		var a := 0.7 * float(i)
		var r := 0.08 + 0.055 * float(i)
		bone.size = Vector3(0.24 + 0.035 * float(i), 0.07, 0.09)
		bone.position = Vector3(cos(a) * r, 0.11 + 0.045 * float(i),
				sin(a) * r * 0.75)
		bone.rotation = Vector3(0, a, 0.22 * sin(a))
		bone.material = Mats.bone()
		bone.use_collision = false
		# The old heap is dressing: the Processor eats what the Collector
		# brings, so this base pile stays visible in front of the mouth.
		bone.set_meta("dressing", true)
		processor_pile.add_child(bone)
	var skull := CSGSphere3D.new()
	skull.radius = 0.12
	skull.scale = Vector3(0.9, 1.2, 1.0)
	skull.position = Vector3(0.08, 0.64, 0.02)
	skull.material = Mats.bone()
	skull.use_collision = false
	skull.set_meta("dressing", true)
	processor_pile.add_child(skull)
	# The pile reads from the hall mouth: one dim amber lamp low over it.
	var pile_lamp := _light(Vector3(px - 0.2, 1.15, pz), Color(1.0, 0.55, 0.24),
			0.65, 3.2)
	pile_lamp.shadow_enabled = true
	# A drain and old feed stains on the chamber floor.
	_box(Vector3(3.4, 0.02, 2.0), Vector3(29.6, 0.02, -11.7), Mats.cable()).use_collision = false


## A scattered remnant of the crew: a bone, a dark wet mass, a torn tag.
## Visual only, so it can never block a drone or a host.
func _remains(pos: Vector3) -> void:
	var part := Node3D.new()
	part.position = pos
	part.rotation.y = randf() * TAU
	add_child(part)
	var long_bone := CSGBox3D.new()
	long_bone.size = Vector3(0.08, 0.07, 0.46)
	long_bone.position = Vector3(0.04, 0.05, 0)
	long_bone.rotation = Vector3(0, 0.5, 0.12)
	long_bone.material = Mats.bone()
	long_bone.use_collision = false
	part.add_child(long_bone)
	var mass := CSGBox3D.new()
	mass.size = Vector3(0.22, 0.08, 0.18)
	mass.position = Vector3(-0.12, 0.04, 0.10)
	mass.rotation = Vector3(0, -0.35, 0)
	mass.material = Mats.cable()
	mass.use_collision = false
	part.add_child(mass)
	var chip := CSGSphere3D.new()
	chip.radius = 0.07
	chip.position = Vector3(0.16, 0.06, 0.14)
	chip.material = Mats.bone()
	chip.use_collision = false
	part.add_child(chip)
	remains.append({"node": part, "pos": pos, "taken": false})


func _galley_stub() -> void:
	# West stub; open east into the junction; the door plane faces west.
	_run(-8.4, -4.6, -30.0, -28.4, 3.0, Mats.wall(), false, false, true, true)
	# Sliding pressure door (slides south into a pocket recess). Thickness
	# nudged 5 cm proud of the wall plane so it never goes coplanar.
	galley_door = _box(Vector3(0.4, 3.0, 1.6),
			Vector3(-8.65, 1.5, DOOR_CLOSED_Z), Mats.machine())
	var l := _light(Vector3(-8.1, 2.6, -29.2), Color(0.8, 0.07, 0.05), 0.4, 3.5)
	set_meta("door_lamp", l)


func _galley() -> void:
	# The crew mess: a proper hall now (12 x 10.4 m), not a cupboard. The
	# player needs a traversal with windows, not a doorway ambush, and the
	# room is deliberately empty so the opening route belongs to the player.
	# Opens east at the door plane.
	_run(-20.4, -8.4, -34.4, -24.0, 3.0, Mats.wall(), false, false, false, true)
	# East face segments either side of the door span.
	_box(Vector3(0.4, 3.0, 4.4), Vector3(-8.6, 1.5, -32.2), Mats.wall())
	_box(Vector3(0.4, 3.0, 4.4), Vector3(-8.6, 1.5, -26.2), Mats.wall())
	# Galley counters along the north wall (solid, but clear of every patrol
	# line — the room's middle stays empty floor on purpose).
	_box(Vector3(3.6, 0.9, 0.6), Vector3(-17.6, 0.45, -34.0), Mats.machine())
	_box(Vector3(3.6, 0.9, 0.6), Vector3(-13.0, 0.45, -34.0), Mats.machine())
	# Mess tables tucked against the south wall.
	_box(Vector3(3.0, 0.9, 0.8), Vector3(-13.5, 0.45, -24.6), Mats.hull())
	_box(Vector3(2.4, 0.9, 0.8), Vector3(-18.2, 0.45, -24.6), Mats.hull())
	# Cold room alcove at the far west (opens east into the galley).
	_run(-19.8, -17.2, -33.8, -31.6, 3.0, Mats.wall(), false, false, false, true)
	# RATIONS: the objective crate stack, deep in the pantry.
	_box(Vector3(0.7, 0.6, 0.7), Vector3(-18.5, 0.3, -32.7), Mats.crate())
	var top := _box(Vector3(0.5, 0.4, 0.5), Vector3(-18.2, 0.8, -32.6), Mats.crate(),
			Vector3(0, 0.4, 0))
	_box(Vector3(0.5, 0.05, 0.02), top.position + Vector3(0, -0.15, -0.26), Mats.amber())


func _dressing() -> void:
	# Loose cables across the bends; ceiling pipes along leg A. Floor-level
	# dressing is VISUAL ONLY — a 12 cm cable is an invisible wall to a
	# capsule or a sled body, and was the thing hosts tripped on.
	var c1 := _cyl(0.05, 2.2, Vector3(-2.3, 0.07, -15.3), Mats.cable(), Vector3(0, 0, PI * 0.5))
	c1.use_collision = false
	var c2 := _cyl(0.05, 6.0, Vector3(-0.2, 0.07, -25.0), Mats.cable(), Vector3(0, 0, PI * 0.5))
	c2.use_collision = false
	for i in 2:
		_cyl(0.08, 8.0, Vector3(-2.3 + 0.25 * i, 2.8, -10.2), Mats.machine(),
				Vector3(0, 0, PI * 0.5))
	# Scattered debris in the junction: a couple of buckled plates (visual).
	var d1 := _box(Vector3(1.2, 0.06, 0.9), Vector3(-3.4, 0.03, -26.6), Mats.hull(), Vector3(0, 0.5, 0))
	d1.use_collision = false
	var d2 := _box(Vector3(0.9, 0.06, 1.1), Vector3(1.8, 0.03, -30.8), Mats.hull(), Vector3(0, 0.2, 0))
	d2.use_collision = false
