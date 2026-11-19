extends Node
## Autoload `PSXLook`: the one owner of the PS1 look in UMBILICAL.
##
## It composes the low-resolution screen, the CSG-aware material conversion,
## the environment/fog/zone-darkness behaviour, the category switches and the
## saved settings. `Main` binds it to the SubViewport hierarchy; everything
## else talks to this node.
##
## Master off is lossless: originals are put back, the screen shader is
## detached, and the authored Environment values are restored.

signal settings_changed

const CONVERT := preload("res://src/psx/psx_convert.gd")
const DENSITY := preload("res://src/psx/psx_density.gd")
const SETTINGS := preload("res://src/psx/psx_settings.gd")
const PRESET_SCRIPT := "res://addons/psx_look/psx_preset.gd"
const CUSTOM_DIR := "user://psx_presets"
## A panel slider fires value_changed for every pixel of a drag; the settings
## file waits this long after the last change instead of being rewritten each
## time, so one drag is one disk write.
const SAVE_DEBOUNCE := 0.35

const DEBUG_AMBIENT_ENERGY := 1.35
const DEBUG_AMBIENT_COLOR := Color(0.92, 0.95, 1.0, 1.0)
const DEBUG_EXPOSURE := 1.55
const DEBUG_FOG := 0.0

const DEFAULTS := {
	"master": true,
	"preset": "ps1",
	"lines": 240,
	"dither": true,
	"color_bits": 5,
	"saturation": 1.0,
	"tint": Color.WHITE,
	"snap_pixels": 1.0,
	"affine": 1.0,
	"three_point": false,
	"vertex_colors": true,
	"texture_bits": 8,
	"texture_size": 0,
	"palette": 0,
	"fog": false,
	"fog_color": Color.BLACK,
	"fog_begin": 5.0,
	"fog_end": 30.0,
	"draw_distance_on": false,
	"draw_distance": 24.0,
	"density": 2.0,
	"conversion": true,
	"sprites": true,
	"flipbooks": true,
	"waves": true,
	"glow": true,
	"cutout": true,
	"transparent": true,
	"chrome": true,
}

var screen: PSXScreen
var viewport: SubViewport
var world: Node3D
var world_environment: WorldEnvironment
var environment: Environment
var main: Node
## Dev scenes (the PSX lab) set this false so the game's saved look is not
## overwritten while experimenting.
var persistence := true

var master := bool(DEFAULTS.master)
var current_preset: StringName = &"ps1"
var lines := int(DEFAULTS.lines)
var dither := bool(DEFAULTS.dither)
var color_bits := int(DEFAULTS.color_bits)
var saturation := float(DEFAULTS.saturation)
var tint: Color = DEFAULTS.tint
var snap_pixels := float(DEFAULTS.snap_pixels)
var affine := float(DEFAULTS.affine)
var three_point := bool(DEFAULTS.three_point)
var vertex_colors := bool(DEFAULTS.vertex_colors)
var texture_bits := int(DEFAULTS.texture_bits)
var texture_size := int(DEFAULTS.texture_size)
var palette := int(DEFAULTS.palette)
var fog := bool(DEFAULTS.fog)
var fog_color: Color = DEFAULTS.fog_color
var fog_begin := float(DEFAULTS.fog_begin)
var fog_end := float(DEFAULTS.fog_end)
var draw_distance_on := bool(DEFAULTS.draw_distance_on)
var draw_distance := float(DEFAULTS.draw_distance)
var density := float(DEFAULTS.density)
var conversion := bool(DEFAULTS.conversion)
var sprites := bool(DEFAULTS.sprites)
var flipbooks := bool(DEFAULTS.flipbooks)
var waves := bool(DEFAULTS.waves)
var glow := bool(DEFAULTS.glow)
var cutout := bool(DEFAULTS.cutout)
var transparent := bool(DEFAULTS.transparent)
var chrome := bool(DEFAULTS.chrome)

var _bound := false
var _entries: Array = []
var _density_records: Array = []
var _cache: Dictionary = {}
var _texture_state: Dictionary = {}
var _category_nodes: Dictionary = {}
var _authored: Dictionary = {}
var _listener: AudioListener3D
var _debug := false
var _zone_dark := 0.0
var _zone_dark_target := 0.0
var _dirty := false
var _sweep_t := 0.0
var _custom: Dictionary = {}
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan_custom_presets()
	_load_settings()


func _process(delta: float) -> void:
	if _listener != null and is_instance_valid(_listener) and viewport != null:
		var cam := viewport.get_camera_3d()
		if cam != null:
			_listener.global_transform = cam.global_transform
	if not _bound:
		return
	_sweep_t += delta
	if _dirty and _sweep_t >= 0.22:
		_dirty = false
		_sweep_t = 0.0
		if master and not _debug and conversion:
			convert_subtree(world)


# --------------------------------------------------------------------------
# Binding
# --------------------------------------------------------------------------

## Called by Main once its PSXScreen/Viewport/World exist. The Environment is
## duplicated here, so the authored .tres is never mutated by zone darkness,
## debug vision or preset fog.
func bind(owner: Node, psx_screen: PSXScreen, node_world: Node3D,
		world_env: WorldEnvironment = null) -> void:
	main = owner
	screen = psx_screen
	viewport = screen.viewport if screen != null else null
	world = node_world
	world_environment = world_env
	if world_environment != null and world_environment.environment != null:
		environment = world_environment.environment.duplicate()
		world_environment.environment = environment
		_snapshot_environment()
	if world != null:
		if _listener != null and is_instance_valid(_listener):
			_listener.queue_free()
		_listener = AudioListener3D.new()
		_listener.name = "PSXAudioListener"
		world.add_child(_listener)
		_listener.make_current()
		if not world.child_entered_tree.is_connected(_on_node_added):
			world.child_entered_tree.connect(_on_node_added)
	_bound = true
	_apply_screen()
	_apply_environment()


## Reconvert everything currently in the world. Main calls this at the end of
## its own _ready, once the bay, ship and initial inhabitants are present.
func refresh() -> void:
	if not _bound:
		return
	if master and not _debug:
		_build()
	else:
		_restore()
		_apply_screen()
	_apply_environment()
	settings_changed.emit()


func current_camera() -> Camera3D:
	if viewport != null:
		return viewport.get_camera_3d()
	return null


func world_3d() -> World3D:
	if viewport == null:
		return null
	# `world_3d` is null when the screen viewport owns its world (own_world_3d).
	# find_world_3d() returns the effective world in both cases.
	return viewport.find_world_3d()


# --------------------------------------------------------------------------
# Master / conversion / density
# --------------------------------------------------------------------------

func set_master(on: bool) -> void:
	if master == on:
		return
	master = on
	if master and not _debug:
		_build()
	else:
		_restore()
	_apply_screen()
	_apply_environment()
	_apply_categories()
	save_settings()
	settings_changed.emit()


func set_conversion(on: bool) -> void:
	if conversion == on:
		return
	conversion = on
	if master and not _debug:
		_build()
	_apply_environment()
	save_settings()
	settings_changed.emit()


func set_density(value: float) -> void:
	if is_equal_approx(density, value):
		return
	density = value
	if master and not _debug:
		_restore()
		_build()
	save_settings()
	settings_changed.emit()


func set_texture_options(size: int, colors: int) -> void:
	if texture_size == size and palette == colors:
		return
	texture_size = size
	palette = colors
	if master and not _debug:
		_cache.clear()
		_texture_state.clear()
		_restore()
		_build()
	save_settings()
	settings_changed.emit()


## Converts a newly spawned subtree (drone, host, wrecks). Idempotent: already
## converted nodes are skipped because their material is no longer a
## BaseMaterial3D.
func convert_subtree(node: Node) -> void:
	if not _bound or not master or _debug or not conversion or node == null:
		return
	if not is_instance_valid(node):
		return
	if density > 0.0:
		var dense := DENSITY.apply(node, density, 18000)
		if not dense.is_empty():
			_density_records.append_array(dense)
	var added := CONVERT.convert(node, _cache)
	if added.is_empty():
		return
	_entries.append_array(added)
	_register_entries(added)
	_apply_material_parameters()
	_apply_categories()


# --------------------------------------------------------------------------
# Screen and material settings
# --------------------------------------------------------------------------

func set_screen_value(key: String, value: Variant) -> void:
	if not _set_field(key, value):
		return
	_apply_screen()
	save_settings()
	settings_changed.emit()


func set_material_value(key: String, value: Variant) -> void:
	if not _set_field(key, value):
		return
	if key == "texture_bits":
		_apply_material_parameters()
	elif key == "fog" or key == "draw_distance_on" or key == "fog_end":
		_apply_material_parameters()
		_apply_environment()
	elif key == "snap_pixels" or key == "affine" or key == "three_point" \
			or key == "vertex_colors" or key == "fog_color" or key == "fog_begin":
		_apply_material_parameters()
	save_settings()
	settings_changed.emit()


func set_draw_distance(on: bool, metres: float = -1.0) -> void:
	if draw_distance_on == on \
			and (metres < 0.0 or is_equal_approx(draw_distance, metres)):
		return
	draw_distance_on = on
	if metres >= 0.0:
		draw_distance = metres
	_apply_material_parameters()
	save_settings()
	settings_changed.emit()


func set_category(category: String, on: bool) -> void:
	if category_on(category) == on:
		return
	match category:
		"sprites": sprites = on
		"flipbooks": flipbooks = on
		"waves": waves = on
		"glow": glow = on
		"cutout": cutout = on
		"transparent": transparent = on
		"chrome": chrome = on
		_: return
	_apply_material_parameters()
	_apply_categories()
	save_settings()
	settings_changed.emit()


func category_on(category: String) -> bool:
	match category:
		"sprites": return sprites
		"flipbooks": return flipbooks
		"waves": return waves
		"glow": return glow
		"cutout": return cutout
		"transparent": return transparent
		"chrome": return chrome
	return true


## Nodes can be tagged at creation (e.g. by the optional art pass or the lab).
func register_category(node: Node, category: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if not _category_nodes.has(id):
		_category_nodes[id] = {
			"node": node,
			"categories": [],
			"original_visible": node.visible,
		}
	var cats: Array = _category_nodes[id].categories
	if not cats.has(category):
		cats.append(category)
	_apply_categories()


# --------------------------------------------------------------------------
# Presets and persistence
# --------------------------------------------------------------------------

func preset_names() -> Array:
	var out: Array = PSXPreset.PRESETS.keys()
	out.append_array(_custom.keys())
	return out


func preset_title(name: StringName) -> String:
	if PSXPreset.PRESETS.has(name):
		return String(PSXPreset.PRESETS[name].get("title", String(name)))
	if _custom.has(String(name)):
		var p = load(_custom[String(name)])
		return p.title if p != null and p.title != "" else String(name)
	return String(name)


func apply_preset(name: StringName, save := true) -> void:
	var p: Resource = null
	if PSXPreset.PRESETS.has(name):
		p = load(PRESET_SCRIPT).named(name)
	elif _custom.has(String(name)):
		p = load(_custom[String(name)])
	if p == null:
		return
	lines = p.lines
	color_bits = p.color_bits
	dither = p.dither
	saturation = p.saturation
	tint = p.tint
	snap_pixels = p.snap_pixels
	affine = p.affine
	three_point = p.three_point
	texture_bits = p.texture_bits
	fog = p.fog
	fog_color = p.fog_color
	fog_begin = p.fog_begin
	fog_end = p.fog_end
	if p.draw_distance > 0.0:
		draw_distance = p.draw_distance
		draw_distance_on = true
	else:
		draw_distance_on = false
	current_preset = name
	_apply_screen()
	_apply_material_parameters()
	_apply_environment()
	if save:
		save_settings()
	settings_changed.emit()


func reset_to_defaults(save := true) -> void:
	master = bool(DEFAULTS.master)
	current_preset = &"ps1"
	for key: String in DEFAULTS:
		if key == "master" or key == "preset":
			continue
		_set_field(key, DEFAULTS[key])
	_cache.clear()
	_texture_state.clear()
	if _bound:
		if master and not _debug:
			_restore()
			_build()
		else:
			_restore()
			_apply_screen()
		_apply_environment()
	if save:
		save_settings()
	settings_changed.emit()


## The write is debounced only: a slider drag calls this dozens of times, so the
## file lands 0.35 s after the last change. Every in-memory value, the applied
## look and settings_changed are already immediate, so panel behaviour does not
## change and the saved content is identical, just written once per drag.
func save_settings() -> void:
	if not persistence:
		return
	if _save_timer == null:
		_save_timer = Timer.new()
		_save_timer.one_shot = true
		_save_timer.wait_time = SAVE_DEBOUNCE
		_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_save_timer.timeout.connect(_flush_settings)
		add_child(_save_timer)
	_save_timer.start(SAVE_DEBOUNCE)


## Writes the pending settings now. Same keys and values as an undebounced save.
func _flush_settings() -> void:
	if _save_timer != null and not _save_timer.is_stopped():
		_save_timer.stop()
	SETTINGS.save(settings_dict())


## The autoload is freed as the tree shuts down, so a write still waiting when
## the player quits lands here (the window's close request only reaches the root
## window, never an autoload).
func _exit_tree() -> void:
	if _save_timer != null and not _save_timer.is_stopped():
		_flush_settings()


func settings_dict() -> Dictionary:
	return {
		"master": master,
		"preset": String(current_preset),
		"lines": lines,
		"dither": dither,
		"color_bits": color_bits,
		"saturation": saturation,
		"tint": tint,
		"snap_pixels": snap_pixels,
		"affine": affine,
		"three_point": three_point,
		"vertex_colors": vertex_colors,
		"texture_bits": texture_bits,
		"texture_size": texture_size,
		"palette": palette,
		"fog": fog,
		"fog_color": fog_color,
		"fog_begin": fog_begin,
		"fog_end": fog_end,
		"draw_distance_on": draw_distance_on,
		"draw_distance": draw_distance,
		"density": density,
		"conversion": conversion,
		"sprites": sprites,
		"flipbooks": flipbooks,
		"waves": waves,
		"glow": glow,
		"cutout": cutout,
		"transparent": transparent,
		"chrome": chrome,
	}


func save_custom_preset(title: String) -> StringName:
	if title.strip_edges() == "":
		title = "Custom"
	if not DirAccess.dir_exists_absolute(CUSTOM_DIR):
		DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var safe := title.to_lower().replace(" ", "_").replace("/", "_").replace("\\", "_")
	var path := "%s/%s.tres" % [CUSTOM_DIR, safe]
	var p := PSXPreset.new()
	p.title = title
	p.lines = lines
	p.color_bits = color_bits
	p.dither = dither
	p.saturation = saturation
	p.tint = tint
	p.snap_pixels = snap_pixels
	p.affine = affine
	p.three_point = three_point
	p.texture_bits = texture_bits
	p.fog = fog
	p.fog_color = fog_color
	p.fog_begin = fog_begin
	p.fog_end = fog_end
	p.draw_distance = draw_distance if draw_distance_on else 0.0
	ResourceSaver.save(p, path)
	_custom[title] = path
	current_preset = StringName(title)
	save_settings()
	settings_changed.emit()
	return current_preset


# --------------------------------------------------------------------------
# Environment / zone darkness / debug
# --------------------------------------------------------------------------

func set_zone_dark(on: bool, delta: float) -> void:
	_zone_dark_target = 1.0 if on else 0.0
	_zone_dark = lerpf(_zone_dark, _zone_dark_target, minf(delta * 1.6, 1.0))
	_apply_environment()


## F4. The look is suspended rather than merely faded: clean colour feed,
## raised ambient, no fog. Turning it off restores the user's exact settings.
func set_debug_vision(on: bool) -> void:
	_debug = on
	if on:
		_restore()
		_apply_screen()
	else:
		if master:
			_build()
		_apply_screen()
	_apply_environment()
	_apply_categories()
	settings_changed.emit()


func debug_suspended() -> bool:
	return _debug


# --------------------------------------------------------------------------
# Internal build/apply
# --------------------------------------------------------------------------

func _build() -> void:
	if not _bound or not master or _debug:
		return
	_restore()
	_apply_screen()
	if conversion:
		if density > 0.0:
			_density_records = DENSITY.apply(world, density)
		_entries = CONVERT.convert(world, _cache)
		if texture_size > 0 or palette > 0:
			CONVERT.shrink_textures(_cache, texture_size, palette, _texture_state)
		_register_entries(_entries)
	_apply_material_parameters()
	_apply_categories()


func _restore() -> void:
	CONVERT.restore(_entries)
	_entries.clear()
	DENSITY.restore(_density_records)
	_density_records.clear()


func _apply_screen() -> void:
	if screen == null:
		return
	screen.lines = lines
	screen.dither = dither
	screen.color_bits = color_bits
	screen.saturation = saturation
	screen.tint = tint
	# Scanlines are retired from the game's look: no setting, preset or old
	# saved file is allowed to bring them back.
	screen.scanlines = 0.0
	screen.look = master and not _debug


func _apply_material_parameters() -> void:
	for source: BaseMaterial3D in _cache.keys():
		var mat: ShaderMaterial = _cache[source]
		mat.set_shader_parameter(&"snap_pixels", snap_pixels)
		mat.set_shader_parameter(&"affine", affine)
		mat.set_shader_parameter(&"three_point", three_point)
		mat.set_shader_parameter(&"vertex_colors", vertex_colors)
		mat.set_shader_parameter(&"texture_bits", texture_bits)
		mat.set_shader_parameter(&"fog_color", fog_color)
		mat.set_shader_parameter(&"fog_begin", fog_begin)
		mat.set_shader_parameter(&"fog_end", fog_end if fog else 0.0)
		mat.set_shader_parameter(&"draw_distance", draw_distance if draw_distance_on else 0.0)
		_apply_flipbook(mat)
		_apply_sprites(mat)
		_apply_waves(mat)


func _apply_flipbook(mat: ShaderMaterial) -> void:
	var fps = mat.get_shader_parameter(&"fps")
	if fps == null:
		return
	if flipbooks:
		if mat.has_meta("psx_fps"):
			mat.set_shader_parameter(&"fps", mat.get_meta("psx_fps"))
			mat.remove_meta("psx_fps")
	else:
		if not mat.has_meta("psx_fps"):
			mat.set_meta("psx_fps", fps)
		mat.set_shader_parameter(&"fps", 0.0)


## Billboards are the sprites' facing. Turning the category off pins every
## billboard to its authored quad; turning it back on restores the source's
## upright/full billboard mode. Only non-zero modes are remembered, so walls
## are not touched.
func _apply_sprites(mat: ShaderMaterial) -> void:
	var value = mat.get_shader_parameter(&"billboard")
	if value == null:
		return
	if sprites:
		if mat.has_meta("psx_billboard"):
			mat.set_shader_parameter(&"billboard", mat.get_meta("psx_billboard"))
			mat.remove_meta("psx_billboard")
	elif not mat.has_meta("psx_billboard") and int(value) != 0:
		mat.set_meta("psx_billboard", value)
		mat.set_shader_parameter(&"billboard", 0)


## Wave motion is a shader displacement, so the switch has to restore each
## material's authored height rather than hide the mesh (the pool or banner
## should still exist, just still).
func _apply_waves(mat: ShaderMaterial) -> void:
	var value = mat.get_shader_parameter(&"wave_height")
	if value == null:
		return
	if waves:
		if mat.has_meta("psx_wave_height"):
			mat.set_shader_parameter(&"wave_height", mat.get_meta("psx_wave_height"))
			mat.remove_meta("psx_wave_height")
	elif not mat.has_meta("psx_wave_height") and not is_zero_approx(float(value)):
		mat.set_meta("psx_wave_height", value)
		mat.set_shader_parameter(&"wave_height", 0.0)


func _apply_categories() -> void:
	var alive := {}
	var look_on := master and not _debug
	for id in _category_nodes.keys():
		var rec: Dictionary = _category_nodes[id]
		var node = rec.get("node")
		if node == null or not is_instance_valid(node):
			continue
		alive[id] = rec
		var visible := bool(rec.get("original_visible", true))
		if visible and look_on:
			for category: String in rec.categories:
				if not category_on(category):
					visible = false
					break
		node.visible = visible
	_category_nodes = alive


func _register_entries(entries: Array) -> void:
	for e: Dictionary in entries:
		var node = e.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var source: BaseMaterial3D = e.get("source")
		var cats: Array = []
		if source != null:
			if source.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				cats.append("glow")
			if source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR \
					or source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
				cats.append("cutout")
			elif source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				cats.append("transparent")
			if source.metallic > 0.5:
				cats.append("chrome")
			if source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
				cats.append("sprites")
		if node.has_meta("psx_categories"):
			for c in node.get_meta("psx_categories"):
				if not cats.has(c):
					cats.append(c)
		if not cats.is_empty():
			node.set_meta("psx_categories", cats)
			var id: int = node.get_instance_id()
			if not _category_nodes.has(id):
				_category_nodes[id] = {
					"node": node,
					"categories": [],
					"original_visible": node.visible,
				}
			for c in cats:
				if not _category_nodes[id].categories.has(c):
					_category_nodes[id].categories.append(c)


func _snapshot_environment() -> void:
	if environment == null:
		return
	_authored = {
		"ambient_energy": environment.ambient_light_energy,
		"ambient_color": environment.ambient_light_color,
		"tonemap_exposure": environment.tonemap_exposure,
		"fog_enabled": environment.fog_enabled,
		"fog_mode": environment.fog_mode,
		"fog_light_color": environment.fog_light_color,
		"fog_light_energy": environment.fog_light_energy,
		"fog_sun_scatter": environment.fog_sun_scatter,
		"fog_aerial_perspective": environment.fog_aerial_perspective,
		"fog_density": environment.fog_density,
		"fog_depth_begin": environment.fog_depth_begin,
		"fog_depth_end": environment.fog_depth_end,
		"fog_sky_affect": environment.fog_sky_affect,
		"background_mode": environment.background_mode,
		"background_color": environment.background_color,
	}


func _apply_environment() -> void:
	if environment == null or _authored.is_empty():
		return
	var dark := _zone_dark
	environment.ambient_light_energy = DEBUG_AMBIENT_ENERGY if _debug \
			else lerpf(float(_authored.ambient_energy), 0.025, dark)
	environment.ambient_light_color = DEBUG_AMBIENT_COLOR if _debug \
			else _authored.ambient_color as Color
	environment.tonemap_exposure = DEBUG_EXPOSURE if _debug \
			else float(_authored.tonemap_exposure)

	if _debug:
		environment.fog_enabled = false
		environment.fog_density = DEBUG_FOG
		environment.background_mode = int(_authored.background_mode)
		environment.background_color = _authored.background_color as Color
		return

	if not master or not fog:
		environment.fog_enabled = bool(_authored.fog_enabled)
		environment.fog_mode = int(_authored.fog_mode)
		environment.fog_light_color = _authored.fog_light_color as Color
		environment.fog_light_energy = float(_authored.fog_light_energy)
		environment.fog_sun_scatter = float(_authored.fog_sun_scatter)
		environment.fog_aerial_perspective = float(_authored.fog_aerial_perspective)
		environment.fog_density = lerpf(float(_authored.fog_density), 0.055, dark)
		environment.fog_depth_begin = float(_authored.fog_depth_begin)
		environment.fog_depth_end = float(_authored.fog_depth_end)
		environment.fog_sky_affect = float(_authored.fog_sky_affect)
		environment.background_mode = int(_authored.background_mode)
		environment.background_color = _authored.background_color as Color
		return

	# PSX depth fog: the materials fog per vertex up to fog_end, the
	# Environment takes everything else from there, in the same colour, so
	# polygons pop in against matching sky rather than a hard line. This mirrors
	# PSXPreset.apply (addons/psx_look/psx_preset.gd, its `if environment and
	# fog:` block): keep the two in step, though this copy also zone-darkens the
	# fog and background and restores them, which the addon does not.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = _darkened(fog_color, dark)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.fog_density = float(_authored.fog_density)
	environment.fog_depth_begin = fog_end
	environment.fog_depth_end = fog_end + 0.01
	environment.fog_sky_affect = 1.0
	if int(_authored.background_mode) == Environment.BG_COLOR:
		environment.background_color = _darkened(fog_color, dark)
	else:
		environment.background_mode = int(_authored.background_mode)
		environment.background_color = _authored.background_color as Color


func _darkened(c: Color, dark: float) -> Color:
	var k := lerpf(1.0, 0.18, dark)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# --------------------------------------------------------------------------
# Settings helpers
# --------------------------------------------------------------------------

func _set_field(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	var old = self.get(key)
	if old == value:
		return false
	self.set(key, value)
	return true


func _load_settings(path := "") -> void:
	if path == "":
		path = SETTINGS.PATH
	var data := SETTINGS.load_data(path)
	if data.is_empty():
		return
	for key in DEFAULTS:
		if not data.has(key):
			continue
		if key == "preset":
			current_preset = StringName(str(data[key]))
		else:
			self.set(key, data[key])
	# A saved "Custom" preset name without a file falls back to PS1.
	if not PSXPreset.PRESETS.has(current_preset) and not _custom.has(String(current_preset)):
		current_preset = &"ps1"


func _scan_custom_presets() -> void:
	_custom.clear()
	if not DirAccess.dir_exists_absolute(CUSTOM_DIR):
		return
	var dir := DirAccess.open(CUSTOM_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".tres"):
			var path := "%s/%s" % [CUSTOM_DIR, file]
			var res = load(path)
			if res is PSXPreset:
				var title: String = res.title if res.title != "" \
						else file.get_basename().replace("_", " ").capitalize()
				_custom[title] = path
		file = dir.get_next()
	dir.list_dir_end()


func _on_node_added(_node: Node) -> void:
	if master and not _debug and conversion:
		_dirty = true
