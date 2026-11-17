extends Node3D
## The demo level, built in plain StandardMaterial3Ds as any project's would be: a ruined courtyard
## at dusk, with torches, a pool, banners, grass and a floating gem in a beam of light over an
## altar. The camera tours it, or walks with WASD or the arrow keys and looks with the mouse held
## down, kept off the walls, pillars, crates, trees, pool and altar. dress() sets what a StandardMaterial3D has no setting for, once PSX.convert has run.

const Shapes := preload("res://addons/psx_look/demo/shapes.gd")

## Seconds into the tour; store scenes pin it for a still.
@export var t := 0.0
@export var touring := true

var cam := Camera3D.new()
var gem: MeshInstance3D
var water: MeshInstance3D
var env := Environment.new()
var torches: Array[OmniLight3D] = []
var flames: Array[MeshInstance3D] = []
var banners: Array[MeshInstance3D] = []
var leaves: Array[MeshInstance3D] = []
var _tex := {}
var _look := Vector2(0.0, -0.15)
var _seed := 0
## Footprints the walk keeps out of, on the ground (x, z), grown by the walker's width.
var _solids: Array[Rect2] = []


func _ready() -> void:
	_environment()
	var ground := _mesh(Shapes.ground(40, 40, 2.0), _mat("grass"))
	add_child(ground)
	for i in 7:
		_add(Shapes.box(Vector3(2.4, 0.06, 2.4), 2.4), _mat("stone"), Vector3(0, 0, 6 - i * 2.4))
	_walls()
	for side: int in [-1, 1]:
		for i in 4:
			var base := Vector3(side * 3.2, 0, 5 - i * 3.6)
			var broken := (i + side + 3) % 3 == 0
			_add(Shapes.pillar(0.42, 1.9 if broken else 3.6, 8, 1.5), _mat("stone"), base)
			_add(Shapes.box(Vector3(1.1, 0.3, 1.1), 1.1), _mat("stone"), base)
			if not broken and (i + int(side > 0)) % 2 == 1:
				_torch(base + Vector3.UP * 3.6)
	for c in [[Vector3(-7.5, 0, 6.5), 0.0], [Vector3(-6.0, 0, 7.0), 0.4], [Vector3(-7.0, 1.2, 6.8), 0.2],
			[Vector3(7.2, 0, -2.5), 0.7], [Vector3(6.8, 0, 4.4), 0.1]]:  # clear of each other and the pool's rim
		_add(Shapes.box(Vector3.ONE * 1.2, 0.0), _mat("crate"), c[0]).rotation.y = c[1]
	for p in [Vector3(-7, 0, -6), Vector3(7.5, 0, 7.6), Vector3(-7.6, 0, 1), Vector3(7.6, 0, -8.5)]:  # leaves clear of the walls
		_tree(p)
	_pool(Vector3(6.5, 0, 1))
	_altar(Vector3(0, 0, -9))
	for x in [-3.6, 3.6]:
		_banner(Vector3(x, 3.7, -12.0))
	_grass()
	add_child(cam)
	cam.current = true
	cam.fov = 70
	for mi in get_children():
		if mi is MeshInstance3D and not (mi.mesh is QuadMesh):  # the sprites (grass, halos) are walked through
			var box: AABB = mi.transform * mi.get_aabb()
			if box.position.y < 1.7 and box.end.y > 0.25:  # standing between the ankle and the eye
				_solids.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.4))
	_process(0.0)


func _process(delta: float) -> void:
	var move := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	for k in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(k[0]):
			move += k[1]
	if move and touring:
		touring = false
		_look = Vector2(cam.rotation.y, cam.rotation.x)
	t += delta
	if touring:
		# Up and down the aisle between the pillars, facing the altar and looking about.
		var a := t * 0.25
		cam.position = Vector3(sin(a) * 1.2, 1.7 + sin(t * 1.3) * 0.05, 2.0 + cos(a) * 4.5)
		cam.look_at(Vector3(sin(t * 0.37) * 6.0, 1.3, -9.0))
	else:
		cam.rotation = Vector3(_look.y, _look.x, 0)
		var dir := cam.basis * Vector3(move.x, 0, move.y)
		var step := Vector3(dir.x, 0, dir.z).normalized() * delta * 4.0 if move else Vector3.ZERO
		for axis in [Vector3(step.x, 0, 0), Vector3(0, 0, step.z)]:  # each axis alone, so a wall is slid along
			if not _enters(cam.position, cam.position + axis):
				cam.position += axis
		cam.position = Vector3(clampf(cam.position.x, -19.0, 19.0), 1.7, clampf(cam.position.z, -19.0, 19.0))  # the ground's edge
	gem.rotation.y = t * 1.2
	gem.position.y = 2.4 + sin(t * 1.8) * 0.15
	for i in torches.size():
		torches[i].light_energy = 2.2 + sin(t * 11.0 + i * 2.0) * 0.25 + sin(t * 17.0 + i) * 0.15
	var m := water.material_override
	if m is BaseMaterial3D:
		m.uv1_offset = Vector3(t * 0.05, t * 0.03, 0)
	elif m is ShaderMaterial:
		m.set_shader_parameter(&"uv_offset", Vector2(t * 0.05, t * 0.03))


func _enters(from: Vector3, to: Vector3) -> bool:
	for r in _solids:
		if r.has_point(Vector2(to.x, to.z)) and not r.has_point(Vector2(from.x, from.z)):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if touring:
			touring = false
			_look = Vector2(cam.rotation.y, cam.rotation.x)
		_look += Vector2(-event.relative.x, -event.relative.y) * 0.005
		_look.y = clampf(_look.y, -1.2, 1.2)


func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://addons/psx_look/demo/sky.gdshader")
	sky_mat.set_shader_parameter(&"top_color", Color(0.12, 0.08, 0.26))
	sky_mat.set_shader_parameter(&"horizon_color", Color(0.85, 0.42, 0.38))
	sky_mat.set_shader_parameter(&"ground_horizon_color", Color(0.85, 0.42, 0.38))
	sky_mat.set_shader_parameter(&"ground_bottom_color", Color(0.1, 0.07, 0.14))
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.34, 0.56)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.46, 0.3, 0.42)
	env.fog_depth_begin = 5.0
	env.fog_depth_end = 30.0
	env.fog_sky_affect = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, -60, 0)
	sun.light_color = Color(1.0, 0.66, 0.46)
	sun.light_energy = 0.9
	add_child(sun)
	sky_mat.set_shader_parameter(&"sun_color", sun.light_color)
	sky_mat.set_shader_parameter(&"sun_energy", sun.light_energy)
	sky_mat.set_shader_parameter(&"sun_direction", sun.basis.z)
	sky_mat.set_shader_parameter(&"srgb", RenderingServer.get_rendering_device() == null)


func _walls() -> void:
	# [centre x, z, length, height, along x]
	for w in [[-6, 10, 8, 3.2, true], [6.5, 10, 7, 2.2, true], [0, -12.5, 20, 4.0, true],
			[-10, 3, 12, 3.0, false], [-10, -9, 7, 1.6, false], [10, -4, 17, 3.4, false]]:
		var size := Vector3(w[2], w[3], 0.8) if w[4] else Vector3(0.8, w[3], w[2])
		_add(Shapes.box(size, 2.0), _mat("brick"), Vector3(w[0], 0, w[1]))


## The flame's flipbook and its halo are additive sprites, PSX Look's glow; without it (the free
## sampler) the flame is a plain cross.
func _torch(p: Vector3) -> void:
	_add(Shapes.box(Vector3(0.5, 0.25, 0.5), 0.5), _mat("planks"), p)
	if PSX.has(&"glow"):
		var flame := _glow("fire", BaseMaterial3D.BILLBOARD_FIXED_Y)
		flame.uv1_scale = Vector3(0.25, 1, 1)  # one frame; dress() plays them
		flames.append(_add(_sprite(Vector2(0.5, 1.0), true), flame, p + Vector3.UP * 0.2))
		_add(_sprite(Vector2.ONE * 1.8, false), _glow("halo", BaseMaterial3D.BILLBOARD_ENABLED), p + Vector3.UP * 0.6)
	else:
		var flame := StandardMaterial3D.new()
		flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.albedo_color = Color(1.0, 0.62, 0.2)
		_add(Shapes.cross(0.35, 0.55), flame, p + Vector3.UP * 0.25)
	var light := OmniLight3D.new()
	light.position = p + Vector3.UP * 0.6
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 7.0
	add_child(light)
	torches.append(light)


func _tree(p: Vector3) -> void:
	_add(Shapes.pillar(0.25, 2.6, 6, 1.0), _mat("bark"), p)
	if not PSX.has(&"cutout"):  # the free sampler's trees go bare
		return
	var leaves := _mat("leaves")
	leaves.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 5:
		var a := TAU * i / 5
		var clump := _add(Shapes.cross(2.4, 2.0), leaves, p + Vector3(cos(a) * 0.7, 1.9 + (i % 2) * 0.7, sin(a) * 0.7))
		clump.rotation.y = a
		self.leaves.append(clump)
	self.leaves.append(_add(Shapes.cross(2.2, 2.0), leaves, p + Vector3.UP * 2.8))


func _pool(p: Vector3) -> void:
	for r in [[Vector3(0, 0, -2.2), Vector3(4.4, 0.5, 0.5)], [Vector3(0, 0, 2.2), Vector3(4.4, 0.5, 0.5)],
			[Vector3(-2.2, 0, 0), Vector3(0.5, 0.5, 3.9)], [Vector3(2.2, 0, 0), Vector3(0.5, 0.5, 3.9)]]:
		_add(Shapes.box(r[1], 1.0), _mat("stone"), p + r[0])
	var m := _mat("water")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.8)
	water = _add(Shapes.ground(3.9, 4, 1.5), m, p + Vector3.UP * 0.35)


func _altar(p: Vector3) -> void:
	_add(Shapes.box(Vector3(3.2, 0.4, 2.2), 1.0), _mat("stone"), p)
	_add(Shapes.box(Vector3(1.8, 0.9, 1.2), 1.0), _mat("stone"), p + Vector3.UP * 0.4)
	var rune := _mat("rune")
	rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add(Shapes.box(Vector3(1.8, 0.02, 1.2), 0.0), rune, p + Vector3.UP * 1.3)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.9, 0.97, 1.0)
	chrome.metallic = 1.0
	chrome.roughness = 0.15
	gem = _add(Shapes.gem(0.45, 1.3), chrome, p + Vector3.UP * 2.4)
	if PSX.has(&"glow"):  # a beam from the sky onto the gem
		var beam := _glow("shaft", BaseMaterial3D.BILLBOARD_DISABLED)
		beam.albedo_color = Color(0.9, 0.78, 0.56)
		_add(Shapes.cone(0.7, 1.3, 5.5, 10), beam, p + Vector3.UP * 1.3)


## Cloth on the back wall, cut into a swallowtail: a cutout.
func _banner(top: Vector3) -> void:
	if not PSX.has(&"cutout"):
		return
	var m := _mat("banner")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	banners.append(_add(Shapes.sheet(Vector2(1.3, 2.6), Vector2i(4, 8)), m, top))


## Tufts of grass, flowers, ferns and weeds about the courtyard, each a frame of one sheet,
## turned to the camera upright.
func _grass() -> void:
	if not PSX.has(&"cutout"):
		return
	var kinds: Array[StandardMaterial3D] = []
	for k in 4:
		var m := _mat("tufts")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.uv1_scale = Vector3(0.25, 1, 1)
		m.uv1_offset = Vector3(k * 0.25, 0, 0)
		kinds.append(m)
	_seed = 7
	var placed := 0
	while placed < 64:
		var p := Vector3(_rand(-9.5, 9.5), 0, _rand(-11.5, 9.5))
		var aisle := absf(p.x) < 1.6 or (absf(absf(p.x) - 3.2) < 0.9 and p.z > -8.0)
		if aisle or Vector2(p.x - 6.5, p.z - 1).length() < 2.8 or (p.z < -7.5 and absf(p.x) < 2.2):
			continue  # the aisle, the pillars' feet, the pool and the altar
		var size := _rand(0.7, 1.1)
		_add(_sprite(Vector2.ONE * size, true), kinds[int(_rand(0.0, 4.0))], p)
		placed += 1


## An LCG, so that the Unity demo's grass grows where this one's does.
func _rand(lo: float, hi: float) -> float:
	_seed = (_seed * 1103515245 + 12345) % 2147483648
	return lo + (hi - lo) * _seed / 2147483648.0


## After PSX.convert: the flames play their frames, the pool ripples, the banners stir from their
## tops and the leaves sway.
func dress() -> void:
	for f in flames:
		PSX.set_param(f, &"frames", Vector2(4, 1))
		PSX.set_param(f, &"fps", 9.0)
		PSX.set_param(f, &"uv_scale", Vector2.ONE)
	PSX.set_param(water, &"wave_height", 0.05)
	PSX.set_param(water, &"wave_length", 1.6)
	for b in banners:
		PSX.set_param(b, &"wave_height", 0.12)
		PSX.set_param(b, &"wave_length", 2.5)
		PSX.set_param(b, &"wave_speed", 0.4)
		PSX.set_param(b, &"wave_pinned", true)
	for l in leaves:
		PSX.set_param(l, &"wave_height", 0.06)
		PSX.set_param(l, &"wave_length", 4.0)
		PSX.set_param(l, &"wave_speed", 0.3)


func _mat(name: String) -> StandardMaterial3D:
	if name not in _tex:
		_tex[name] = load("res://addons/psx_look/demo/art/%s.png" % name)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex[name]
	m.roughness = 0.9
	return m


func _glow(name: String, billboard: BaseMaterial3D.BillboardMode) -> StandardMaterial3D:
	var m := _mat(name)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = billboard
	return m


## A quad facing +Z, standing on its foot or about its middle.
func _sprite(size: Vector2, upright: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	if upright:
		q.center_offset = Vector3(0, size.y * 0.5, 0)
	return q


func _add(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := _mesh(mesh, mat)
	mi.position = pos
	add_child(mi)
	return mi


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi
