class_name FabBay
extends Node3D
## M0 graybox: the fabrication bay — one sealed room the player cannot leave.
## Heavy utilitarian geometry (CSG + code), two practical lights, one flicker
## over the map table, one red emergency pulse over the barricaded door.
## (Refs resolved via preload consts so headless cold runs parse cleanly.)

const Mats := preload("res://src/mats.gd")
const Interactable := preload("res://src/interact/interactable.gd")
##
## Layout ("FWD ◄ escape" is a later build; everything here is mid-ship):
##   west end  = pilot nook (chair, desk, dormant screen wall) + exterior door
##               (barricaded) + interior hatch on the north wall
##   center    = map table
##   north-east= fabricator
##   east      = supply lockers
##   scattered = crates, barrel, cable runs, ceiling pipes

var player_start := Vector3(4.8, 0.2, 2.8)

var pilot_chair = null
var fabricator = null
var map_table = null
var map_surface: MeshInstance3D = null
var _flicker: OmniLight3D
var _emergency: OmniLight3D
var _flicker_base := 0.85
var _fnoise := FastNoiseLite.new()
var _t := 0.0


func build() -> void:
	_fnoise.frequency = 8.0
	_shell()
	_pilot_nook()
	_fabricator()
	_map_table()
	_lockers()
	_door_barricade()
	_hatch()
	_scatter()
	_lights()


func _process(delta: float) -> void:
	_t += delta
	if _flicker != null:
		# Slow sickly wander with rare near-outages.
		var v := _fnoise.get_noise_1d(_t * 3.0)
		var drop := sin(_t * 13.7) > 0.985
		_flicker.light_energy = _flicker_base * (0.7 + 0.3 * v) * (0.12 if drop else 1.0)
	if _emergency != null:
		_emergency.light_energy = 0.32 + 0.18 * sin(_t * 2.1)


# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------

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


func _interact(pos: Vector3, size: Vector3, prompt: String, lines: Array) -> Interactable:
	var it := Interactable.new()
	it.position = pos
	it.shape_size = size
	it.prompt = prompt
	for line in lines:
		it.lines.append(str(line))
	add_child(it)
	return it


# --------------------------------------------------------------------------
# Shell: floor / ceiling / walls. West wall has the exterior door gap.
# --------------------------------------------------------------------------

func _shell() -> void:
	# Interior: x -7..7, z -5..5, h 3.6.
	_box(Vector3(15.6, 0.4, 11.6), Vector3(0, -0.2, 0), Mats.deck())      # floor
	_box(Vector3(15.6, 0.4, 11.6), Vector3(0, 3.9, 0), Mats.ceil())       # ceiling
	_box(Vector3(15.6, 4.0, 0.4), Vector3(0, 1.8, -5.2), Mats.wall())     # north
	_box(Vector3(15.6, 4.0, 0.4), Vector3(0, 1.8, 5.2), Mats.wall())      # south
	_box(Vector3(0.4, 4.0, 11.6), Vector3(7.2, 1.8, 0), Mats.wall())      # east
	# West wall in two segments, leaving a z 1.0..2.6 gap = the exterior door.
	_box(Vector3(0.4, 4.0, 6.0), Vector3(-7.2, 1.8, -2.0), Mats.wall())
	_box(Vector3(0.4, 4.0, 2.4), Vector3(-7.2, 1.8, 3.8), Mats.wall())
	_box(Vector3(0.4, 1.1, 1.6), Vector3(-7.2, 3.05, 1.8), Mats.wall())   # lintel


# --------------------------------------------------------------------------
# West end: pilot nook.
# --------------------------------------------------------------------------

func _pilot_nook() -> void:
	# Dormant screen wall (the drone feed goes live here in M1+).
	_box(Vector3(0.12, 2.0, 3.0), Vector3(-6.9, 1.7, -1.6), Mats.screen_off())
	_box(Vector3(0.1, 0.8, 1.0), Vector3(-6.85, 2.3, -3.4), Mats.screen_off())
	_box(Vector3(0.1, 0.6, 0.8), Vector3(-6.85, 1.0, 0.6), Mats.screen_off())

	# Console desk in front of the screens.
	_box(Vector3(0.5, 0.1, 2.6), Vector3(-6.25, 1.02, -1.6), Mats.hull())
	_box(Vector3(0.4, 0.95, 2.2), Vector3(-6.3, 0.5, -1.6), Mats.machine())

	# The pilot chair (faces -X). Base, seat, back, stalk.
	_cyl(0.24, 0.1, Vector3(-5.2, 0.05, -1.6), Mats.machine())
	_cyl(0.09, 0.5, Vector3(-5.2, 0.32, -1.6), Mats.machine())
	_box(Vector3(0.62, 0.12, 0.58), Vector3(-5.2, 0.6, -1.6), Mats.hull())
	_box(Vector3(0.12, 0.78, 0.58), Vector3(-4.92, 1.02, -1.6), Mats.hull())

	# The pilot chair: in M1 pressing E here launches a tethered drone sortie
	# (behavior wired by Main through on_interact).
	pilot_chair = _interact(Vector3(-5.2, 0.75, -1.6), Vector3(0.9, 1.7, 0.8),
			"Sit - bring up the drone", [])


func _fabricator() -> void:
	_box(Vector3(1.7, 2.0, 1.0), Vector3(3.4, 1.0, -3.6), Mats.machine())
	_cyl(0.4, 0.6, Vector3(3.4, 2.3, -3.6), Mats.hull())
	_box(Vector3(0.5, 0.5, 0.55), Vector3(3.4, 0.95, -2.95), Mats.hull())
	# Powered tell strip.
	_box(Vector3(1.25, 0.06, 0.02), Vector3(3.4, 1.55, -3.06), Mats.amber())

	fabricator = _interact(Vector3(3.4, 1.1, -3.4), Vector3(2.0, 2.3, 1.5), "Use fabricator", [])


func _map_table() -> void:
	_box(Vector3(1.9, 0.07, 1.0), Vector3(0.4, 0.92, 0.0), Mats.hull())
	for offset in [Vector3(-0.86, 0, -0.42), Vector3(0.86, 0, -0.42),
			Vector3(-0.86, 0, 0.42), Vector3(0.86, 0, 0.42)]:
		_box(Vector3(0.08, 0.9, 0.08), Vector3(0.4, 0.45, 0.0) + offset, Mats.machine())
	# Paper map on top.
	_box(Vector3(1.55, 0.015, 0.78), Vector3(0.4, 0.97, 0.0), Mats.paper())

	# The live map surface: a quad just above the paper, textured with the
	# hand-copy map (radar ink fills it in across sorties). Main assigns the
	# SubViewport texture; the material is prepared here.
	map_surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.75)
	map_surface.mesh = quad
	map_surface.rotation = Vector3(-PI * 0.5, 0, 0)
	map_surface.position = Vector3(0.4, 0.978, 0.0)
	var map_mat := StandardMaterial3D.new()
	map_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	map_mat.roughness = 0.92
	map_surface.material_override = map_mat
	add_child(map_surface)

	map_table = _interact(Vector3(0.4, 0.9, 0.0), Vector3(2.0, 1.0, 1.0), "Read map", [])


func _lockers() -> void:
	_box(Vector3(0.5, 2.0, 0.62), Vector3(6.75, 1.0, -1.2), Mats.hull())
	_box(Vector3(0.5, 2.0, 0.62), Vector3(6.75, 1.0, -0.5), Mats.hull())
	# One ajar, leaning out.
	_box(Vector3(0.5, 2.0, 0.62), Vector3(6.55, 1.0, 0.45), Mats.hull(), Vector3(0, 0.25, 0))

	_interact(Vector3(6.7, 1.0, -0.3), Vector3(1.0, 2.2, 2.4), "Search lockers", [
		"Empty.",
	])


# --------------------------------------------------------------------------
# West door: barricaded from inside. South of the lintel gap.
# --------------------------------------------------------------------------

func _door_barricade() -> void:
	_box(Vector3(0.18, 2.2, 1.5), Vector3(-7.3, 1.05, 1.8), Mats.hull())     # door leaf
	_box(Vector3(0.1, 0.16, 2.3), Vector3(-7.05, 0.95, 1.8), Mats.crate(),
			Vector3(0, 0, 0.42))
	_box(Vector3(0.1, 0.16, 2.3), Vector3(-7.05, 1.72, 1.8), Mats.crate(),
			Vector3(0, 0, -0.38))
	# Short brace across the middle so the two long planks read as a set, not
	# as debris.
	_box(Vector3(0.1, 0.12, 1.6), Vector3(-7.05, 1.34, 1.8), Mats.crate())

	_interact(Vector3(-7.2, 1.2, 1.8), Vector3(0.9, 2.4, 2.0), "Barricade", [
		"Barricaded from inside.",
	])


# --------------------------------------------------------------------------
# North hatch: to the rest of the ship (locked).
# --------------------------------------------------------------------------

func _hatch() -> void:
	_cyl(0.5, 0.12, Vector3(-2.0, 1.15, -5.02), Mats.machine(), Vector3(1.5708, 0, 0))
	_box(Vector3(0.12, 0.12, 0.34), Vector3(-2.0, 1.15, -4.92), Mats.hull())

	# Antenna mast + dish next to the pilot nook: the sortie's lifeline.
	_cyl(0.05, 1.5, Vector3(-6.45, 0.75, 1.6), Mats.machine())
	_box(Vector3(0.55, 0.4, 0.08), Vector3(-6.3, 1.7, 1.6), Mats.hull(),
			Vector3(0.5, 0.9, 0))
	_box(Vector3(0.08, 0.08, 0.08), Vector3(-6.2, 1.85, 1.62), Mats.amber())

	_interact(Vector3(-2.0, 1.15, -5.0), Vector3(1.3, 1.5, 0.6), "Drone hatch", [
		"Locked.",
	])


# --------------------------------------------------------------------------
# Scatter: crates, barrel, cable runs, ceiling pipes. Pure furniture; none of
# it is interactable in M0 — the bay reads through silhouettes.
# --------------------------------------------------------------------------

func _scatter() -> void:
	_box(Vector3(0.85, 0.5, 0.85), Vector3(-3.6, 0.25, 2.8), Mats.crate())
	_box(Vector3(0.7, 0.5, 0.7), Vector3(-3.5, 0.75, 2.7), Mats.crate(), Vector3(0, 0.3, 0))
	_box(Vector3(0.8, 0.7, 0.8), Vector3(2.2, 0.35, 2.4), Mats.crate(), Vector3(0, -0.2, 0))
	_cyl(0.3, 0.95, Vector3(4.6, 0.475, -0.9), Mats.hull())

	# Tether cable run: door area down the center aisle toward the pilot chair.
	# Floor cables: visual only (ankle-height scenery, never collision).
	for i in 3:
		var bay_cable := _cyl(0.045, 11.5, Vector3(-0.1 + i * 0.09, 0.07, -1.15 + i * 0.12),
				Mats.cable(), Vector3(0, 0, 1.5708))
		bay_cable.use_collision = false
	var bay_cable2 := _cyl(0.045, 5.0, Vector3(2.6, 0.07, -2.9), Mats.cable(), Vector3(0, 0, 1.5708))
	bay_cable2.use_collision = false
	var bay_cable3 := _cyl(0.1, 6.0, Vector3(5.6, 0.09, 2.2), Mats.cable(), Vector3(0, 0, 1.5708))
	bay_cable3.use_collision = false

	# Ceiling pipes along the north side.
	_cyl(0.09, 14.0, Vector3(0, 3.4, -4.6), Mats.machine(), Vector3(0, 0, 1.5708))
	_cyl(0.07, 14.0, Vector3(0, 3.55, -4.3), Mats.machine(), Vector3(0, 0, 1.5708))

	# Vent grate high on the south wall.
	_box(Vector3(1.2, 0.5, 0.1), Vector3(-1.5, 2.9, 5.05), Mats.machine())


# --------------------------------------------------------------------------
# Practical lights.
# --------------------------------------------------------------------------

func _lights() -> void:
	var main_light := OmniLight3D.new()
	main_light.position = Vector3(2.6, 3.3, 0.4)
	main_light.light_color = Color(1.0, 0.86, 0.68)
	main_light.light_energy = 1.0
	main_light.omni_range = 8.5
	main_light.shadow_enabled = true
	add_child(main_light)

	var cool := OmniLight3D.new()
	cool.position = Vector3(-3.4, 3.3, -2.4)
	cool.light_color = Color(0.85, 0.9, 1.0)
	cool.light_energy = 0.72
	cool.omni_range = 7.0
	cool.shadow_enabled = true
	add_child(cool)

	# Flicker over the map table.
	_flicker = OmniLight3D.new()
	_flicker.position = Vector3(0.4, 3.15, 0.0)
	_flicker.light_color = Color(1.0, 0.9, 0.75)
	_flicker.light_energy = _flicker_base
	_flicker.omni_range = 6.0
	add_child(_flicker)

	# Red emergency pulse over the barricaded door.
	_emergency = OmniLight3D.new()
	_emergency.position = Vector3(-6.5, 2.95, 1.8)
	_emergency.light_color = Color(0.8, 0.08, 0.05)
	_emergency.light_energy = 0.4
	_emergency.omni_range = 4.5
	add_child(_emergency)
