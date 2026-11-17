extends Node
## PSX Look integration probe. Covers the viewport/world move, CSG-aware
## conversion and lossless master restore, density, presets, every live
## toggle, runtime spawns, the still-photo feed, the table map exclusion,
## debug F4 suspension, settings persistence and the crisp options panel.
##
## Run: godot --headless --path . res://tests/psx_look.tscn

const PRESET_SCRIPT := "res://addons/psx_look/psx_preset.gd"
const PSX_SHADER_PREFIX := "res://addons/psx_look/"

var _failed := false


class MouseSink extends Node:
	var motions := 0

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			motions += 1


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_failed = true


func _is_psx_material(material: Material) -> bool:
	var sh := material as ShaderMaterial
	return sh != null and sh.shader != null \
			and sh.shader.resource_path.begins_with(PSX_SHADER_PREFIX)


func _count_psx(nodes: Array) -> int:
	var n := 0
	for node in nodes:
		if node is GeometryInstance3D and _is_psx_material(node.material_override):
			n += 1
	return n


func _find_small_csg(root: Node) -> CSGShape3D:
	for node in root.find_children("*", "CSGShape3D", true, false):
		if not (node is CSGPrimitive3D):
			continue
		if (node as CSGPrimitive3D).material is BaseMaterial3D:
			return node as CSGShape3D
	return null


func _press_f4(main) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F4
	ev.keycode = KEY_F4
	ev.pressed = true
	main._input(ev)


func _run() -> void:
	await get_tree().physics_frame
	PSXLook.reset_to_defaults(false)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 5:
		await get_tree().physics_frame
	main._on_start_clicked.call_deferred()
	for _i in 10:
		await get_tree().physics_frame
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame

	# --- World under the PSX screen --------------------------------------
	_check(main.world != null and main.world.get_parent() == main.psx_screen.viewport,
			"the 3D World lives inside PSXScreen's SubViewport")
	_check(main.psx_screen.viewport.own_world_3d,
			"the PSX viewport owns its own World3D")
	_check(PSXLook.world_3d() != null
			and PSXLook.world_3d() == main.psx_screen.viewport.find_world_3d(),
			"PSXLook exposes the screen viewport's effective World3D")
	_check(main.world.get_viewport() == main.psx_screen.viewport,
			"the gameplay camera reports the PSX viewport")
	_check(PSXLook.current_camera() == main.player.cam,
			"the on-foot camera is current in the PSX viewport")
	_check(main.hud.get_parent() == main and main.hud is CanvasLayer,
			"the HUD stays outside the PSX viewport")
	_check(main.psx_screen.get_parent() is CanvasLayer,
			"the PSX screen is a CanvasLayer control")

	# --- Mouse look survives the viewport move ---------------------------
	# SubViewportContainer forwards positional mouse events to its SubViewport
	# through gui_input, so MOUSE_FILTER_IGNORE would silently kill mouse look.
	_check(main.psx_screen.mouse_filter != Control.MOUSE_FILTER_IGNORE,
			"the PSX screen accepts mouse input so it can forward it")
	_check(main.hud._title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the fading title lets mouse motion through")
	# Headless has no window, so the engine never sends the mouse-enter
	# notification that lets the root viewport route GUI mouse motion, and the
	# 64x64 test viewport leaves the HUD covering the PSX screen. Supply both
	# pieces of OS/geometry setup, then push a real motion event into the root
	# viewport: the container's own gui_input -> SubViewport -> _input chain is
	# what has to carry it to gameplay, so that is the path under test here.
	var root_vp := get_viewport()
	root_vp.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
	main.hud.visible = false

	var sink := MouseSink.new()
	main.world.add_child(sink)
	var motion := InputEventMouseMotion.new()
	motion.position = root_vp.get_visible_rect().size * 0.5
	motion.relative = Vector2(24.0, 0.0)
	root_vp.push_input(motion)
	await get_tree().process_frame
	_check(sink.motions > 0,
			"mouse motion reaches gameplay through the PSX viewport")
	sink.queue_free()

	main.hud.visible = true

	var env_node := main.world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check(env_node != null and env_node.environment == PSXLook.environment,
			"the runtime Environment lives inside the PSX world")
	_check(PSXLook.environment != load("res://assets/environment.tres"),
			"the authored Environment resource is duplicated, not mutated")

	# --- Density (default 2 m) -------------------------------------------
	var dense: Array = main.ship.find_children("PSXDense", "MeshInstance3D", true, false)
	var dense_world: Array = main.world.find_children("PSXDense", "MeshInstance3D", true, false)
	_check(dense_world.size() > 0,
			"default density bakes long CSG faces (%d meshes)" % dense_world.size())
	_check(PSXLook._density_records.size() == dense_world.size(),
			"every bake has one lossless density record (%d/%d)"
			% [PSXLook._density_records.size(), dense_world.size()])
	var hidden := 0
	for b in dense_world:
		var parent: Node = b.get_parent()
		if parent != null and parent.has_meta("psx_density_hidden"):
			hidden += 1
	_check(hidden == dense_world.size(),
			"each densified CSG is hidden behind a discard override (%d)" % hidden)
	_check(_count_psx(dense_world) == dense_world.size(),
			"every dense replacement mesh is PSX-converted")

	PSXLook.refresh()
	await get_tree().physics_frame
	var after_dense: Array = main.world.find_children("PSXDense", "MeshInstance3D", true, false)
	var records_after: int = PSXLook._density_records.size()
	var entries_after: int = PSXLook._entries.size()
	_check(after_dense.size() == dense_world.size(),
			"a rebuild does not duplicate density bakes (%d/%d)"
			% [after_dense.size(), dense_world.size()])
	_check(records_after == after_dense.size(),
			"a rebuild keeps one record per bake")
	PSXLook.refresh()
	await get_tree().physics_frame
	var again: Array = main.world.find_children("PSXDense", "MeshInstance3D", true, false)
	_check(again.size() == after_dense.size(),
			"repeated builds keep the bake count stable (%d)" % again.size())
	_check(PSXLook._density_records.size() == records_after,
			"repeated builds keep the record count stable")
	_check(PSXLook._entries.size() == entries_after,
			"repeated builds do not grow conversion entries")

	# --- CSG conversion without density ----------------------------------
	PSXLook.set_density(0.0)
	await get_tree().physics_frame
	var left: Array = main.ship.find_children("PSXDense", "MeshInstance3D", true, false)
	_check(left.is_empty(), "density off removes every bake")
	var ship_csg: Array = main.ship.find_children("*", "CSGShape3D", true, false)
	_check(_count_psx(ship_csg) > 50,
			"ship CSG geometry converts (%d overrides)" % _count_psx(ship_csg))
	var drone_csg: Array = main.drone.find_children("*", "CSGShape3D", true, false)
	_check(drone_csg.size() > 0 and _count_psx(drone_csg) == drone_csg.size(),
			"actor CSG geometry converts (%d/%d)" % [_count_psx(drone_csg), drone_csg.size()])

	var sample := _find_small_csg(main.ship)
	_check(sample != null, "a ship CSG with an authored material is available")
	if sample != null:
		var prim := sample as CSGPrimitive3D
		var authored: Material = prim.material
		_check(sample.material_override != null and _is_psx_material(sample.material_override),
				"the sample CSG carries a PSX shader override")
		_check(prim.material == authored, "the authored CSG material is untouched")

		# --- Master off restores the authored look exactly ---------------
		PSXLook.set_master(false)
		await get_tree().physics_frame
		_check(not PSXLook.master, "master switch reports off")
		_check(sample.material_override == null,
				"master off restores the CSG override to its authored null")
		_check(not main.psx_screen.look and main.psx_screen.material == null,
				"master off detaches the PSX screen shader")
		_check(PSXLook._entries.is_empty(), "master off clears conversion records")

		PSXLook.set_master(true)
		await get_tree().physics_frame
		_check(PSXLook.master and sample.material_override != null
				and _is_psx_material(sample.material_override),
				"master on reconverts the CSG geometry")
		_check(main.psx_screen.look and main.psx_screen.material != null,
				"master on reattaches the PSX screen shader")

	# --- Runtime spawn converts ------------------------------------------
	var fleet_before: int = main.drones.size()
	main._deploy_drone()
	await get_tree().physics_frame
	_check(main.drones.size() == fleet_before + 1,
			"a runtime chassis joins the fleet (%d)" % main.drones.size())
	var fresh: Node = main.drones[main.drones.size() - 1]
	var fresh_csg: Array = fresh.find_children("*", "CSGShape3D", true, false)
	_check(fresh_csg.size() > 0 and _count_psx(fresh_csg) == fresh_csg.size(),
			"runtime-spawned CSG converts immediately (%d/%d)"
			% [_count_psx(fresh_csg), fresh_csg.size()])

	# --- Still photo feed and table map ----------------------------------
	_check(main._feed_vp != null and main._feed_vp.size == Vector2i(480, 270),
			"the still-photo viewport is 480x270")
	_check(main._feed_vp.world_3d != null
			and main._feed_vp.world_3d == PSXLook.world_3d()
			and main._feed_vp.world_3d == main.psx_screen.viewport.find_world_3d(),
			"the still photo renders the PSX World3D")
	_check(main._feed_vp.get_camera_3d() == main._feed_cam
			and main._feed_cam.is_current(),
			"the still photo's camera is current in its own viewport")
	_check(main._feed_vp.get_parent() == main,
			"the still photo stays outside the low-resolution world")
	_check(main.level.map_surface.has_meta("psx_exclude"),
			"the table map surface is excluded from conversion")
	var map_mat := main.level.map_surface.material_override as StandardMaterial3D
	_check(map_mat != null and map_mat.albedo_texture is ViewportTexture,
			"the table map keeps its authored material and live texture")

	# --- All thirteen presets --------------------------------------------
	var preset_script = load(PRESET_SCRIPT)
	var names: Array = preset_script.PRESETS.keys()
	_check(names.size() == 13, "the pack ships thirteen presets (%d)" % names.size())
	var preset_fail := []
	for name: StringName in names:
		PSXLook.apply_preset(name, false)
		var p = preset_script.named(name)
		var ok: bool = PSXLook.lines == p.lines \
				and PSXLook.color_bits == p.color_bits \
				and PSXLook.dither == p.dither \
				and is_equal_approx(PSXLook.saturation, p.saturation) \
				and PSXLook.tint == p.tint \
				and is_zero_approx(PSXLook.screen.scanlines) \
				and is_zero_approx(float(PSXLook.screen._color.get_shader_parameter("scanlines"))) \
				and is_equal_approx(PSXLook.snap_pixels, p.snap_pixels) \
				and is_equal_approx(PSXLook.affine, p.affine) \
				and PSXLook.three_point == p.three_point \
				and PSXLook.texture_bits == p.texture_bits \
				and PSXLook.fog == p.fog \
				and is_equal_approx(PSXLook.fog_begin, p.fog_begin) \
				and is_equal_approx(PSXLook.fog_end, p.fog_end) \
				and main.psx_screen.lines == p.lines
		if p.draw_distance > 0.0:
			ok = ok and PSXLook.draw_distance_on \
					and is_equal_approx(PSXLook.draw_distance, p.draw_distance)
		else:
			ok = ok and not PSXLook.draw_distance_on
		if not ok:
			preset_fail.append(String(name))
	_check(preset_fail.is_empty(),
			"all thirteen presets apply screen and material values (%s)"
			% str(preset_fail))
	# CRT is the pack's scanline preset; the game keeps its other values but
	# swallows the scanlines.
	PSXLook.apply_preset(&"crt", false)
	_check(is_zero_approx(PSXLook.screen.scanlines) \
			and is_zero_approx(float(PSXLook.screen._color.get_shader_parameter("scanlines"))),
			"the CRT preset cannot enable scanlines")
	_check(PSXLook.screen.look, "presets keep the look on")

	# --- Every live toggle reaches the screen or the materials -----------
	PSXLook.apply_preset(&"ps1", false)
	var mat: ShaderMaterial = PSXLook._cache.values()[0] if not PSXLook._cache.is_empty() else null
	_check(mat != null, "the converted world exposes shared PSX materials")
	if mat != null:
		PSXLook.set_material_value("snap_pixels", 0.0)
		_check(is_zero_approx(float(mat.get_shader_parameter("snap_pixels"))),
				"vertex snap toggle reaches the materials")
		PSXLook.set_material_value("snap_pixels", 1.0)

		PSXLook.set_material_value("affine", 0.0)
		_check(is_zero_approx(float(mat.get_shader_parameter("affine"))),
				"affine toggle reaches the materials")
		PSXLook.set_material_value("affine", 1.0)

		PSXLook.set_material_value("three_point", true)
		_check(bool(mat.get_shader_parameter("three_point")),
				"three-point filter toggle reaches the materials")
		PSXLook.set_material_value("three_point", false)

		PSXLook.set_material_value("vertex_colors", false)
		_check(not bool(mat.get_shader_parameter("vertex_colors")),
				"vertex-colour toggle reaches the materials")
		PSXLook.set_material_value("vertex_colors", true)

		PSXLook.set_material_value("texture_bits", 4)
		_check(int(mat.get_shader_parameter("texture_bits")) == 4,
				"texture colour depth reaches the materials")
		PSXLook.set_material_value("texture_bits", 8)

		PSXLook.set_material_value("fog", true)
		_check(is_equal_approx(float(mat.get_shader_parameter("fog_end")), PSXLook.fog_end),
				"PS1 fog toggle reaches the materials")
		PSXLook.set_material_value("fog", false)

		PSXLook.set_draw_distance(true, 24.0)
		_check(is_equal_approx(float(mat.get_shader_parameter("draw_distance")), 24.0),
				"draw distance reaches the materials")
		PSXLook.set_draw_distance(false)

	PSXLook.set_screen_value("scanlines", 0.4)
	_check(is_zero_approx(PSXLook.screen.scanlines) \
			and is_zero_approx(float(PSXLook.screen._color.get_shader_parameter("scanlines"))),
			"screen values cannot set scanlines")
	PSXLook.set_screen_value("dither", false)
	_check(not bool(PSXLook.screen._color.get_shader_parameter("dither")),
			"dither toggle reaches the PSX screen")
	PSXLook.set_screen_value("dither", true)
	PSXLook.set_screen_value("color_bits", 4)
	_check(int(PSXLook.screen._color.get_shader_parameter("color_bits")) == 4,
			"screen colour depth reaches the PSX screen")
	PSXLook.set_screen_value("color_bits", 5)
	PSXLook.set_screen_value("tint", Color(1.0, 0.8, 0.6))
	_check(PSXLook.screen.tint == Color(1.0, 0.8, 0.6),
			"screen tint reaches the PSX screen")
	PSXLook.set_screen_value("tint", Color.WHITE)
	PSXLook.set_screen_value("lines", 192)
	_check(PSXLook.screen.lines == 192, "resolution control reaches the PSX screen")
	PSXLook.set_screen_value("lines", 240)

	# Category switches: a tagged sprite hides and master off shows it again.
	var tagged := MeshInstance3D.new()
	tagged.name = "PSXTaggedProbe"
	tagged.mesh = QuadMesh.new()
	tagged.material_override = PSX.make(&"glow")
	main.world.add_child(tagged)
	PSXLook.register_category(tagged, "glow")
	PSXLook.set_category("glow", false)
	_check(not tagged.visible, "a category switch hides its tagged nodes")
	PSXLook.set_master(false)
	_check(tagged.visible, "master off shows authored nodes again")
	PSXLook.set_master(true)
	_check(not tagged.visible, "master on reapplies the category switch")
	PSXLook.set_category("glow", true)
	_check(tagged.visible, "turning the category back on shows the node")
	tagged.queue_free()

	PSXLook.set_texture_options(64, 16)
	_check(PSXLook.texture_size == 64 and PSXLook.palette == 16,
			"texture size and palette settings are stored")
	PSXLook.set_texture_options(0, 0)

	# --- Debug F4 suspends and restores ----------------------------------
	var debug_sample := _find_small_csg(main.ship)
	_press_f4(main)
	await get_tree().physics_frame
	_check(PSXLook.debug_suspended(), "F4 suspends the PSX look")
	_check(not main.psx_screen.look and main.psx_screen.material == null,
			"F4 detaches the low-resolution screen")
	if debug_sample != null:
		_check(debug_sample.material_override == null or
				not _is_psx_material(debug_sample.material_override),
				"F4 restores authored geometry for the clean feed")
	_press_f4(main)
	await get_tree().physics_frame
	_check(not PSXLook.debug_suspended(), "F4 returns control to the look")
	_check(main.psx_screen.look and main.psx_screen.material != null,
			"F4 off reattaches the PSX screen")
	if debug_sample != null:
		_check(debug_sample.material_override != null
				and _is_psx_material(debug_sample.material_override),
				"F4 off reconverts the geometry")

	# --- Settings round-trip ---------------------------------------------
	var settings: Dictionary = PSXLook.settings_dict()
	settings["tint"] = Color(0.9, 0.7, 0.5)
	settings["snap_pixels"] = 2.5
	var temp := "user://psx_look_test.cfg"
	_check(PSXSettings.save(settings, temp) == OK, "settings save to disk")
	var back := PSXSettings.load_data(temp)
	_check(back.get("tint") == Color(0.9, 0.7, 0.5) \
			and is_equal_approx(float(back.get("snap_pixels", 0.0)), 2.5) \
			and int(back.get("color_bits", 0)) == int(settings["color_bits"]) \
			and bool(back.get("fog", true)) == bool(settings["fog"]),
			"settings survive a save/load round-trip")
	_check(not settings.has("scanlines"), "saved settings carry no scanline field")
	PSXSettings.remove(temp)
	_check(not FileAccess.file_exists(temp), "the temporary settings file is removed")

	# An old settings file still has its scanline key; loading it must ignore it.
	var legacy: Dictionary = settings.duplicate()
	legacy["scanlines"] = 0.75
	var legacy_path := "user://psx_look_test_legacy.cfg"
	_check(PSXSettings.save(legacy, legacy_path) == OK,
			"a legacy settings file with a scanline key writes")
	PSXLook._load_settings(legacy_path)
	_check(is_zero_approx(PSXLook.screen.scanlines) \
			and is_zero_approx(float(PSXLook.screen._color.get_shader_parameter("scanlines"))),
			"loading old settings cannot revive scanlines")
	PSXSettings.remove(legacy_path)
	_check(not FileAccess.file_exists(legacy_path),
			"the legacy settings file is removed")

	# --- Crisp panel ------------------------------------------------------
	main._open_psx()
	_check(main._psx_open and main.hud.psx_panel_open() and main._paused,
			"F5-style open shows the crisp panel and pauses play")
	var sliders: Array = main.hud._psx_panel.find_children("*", "HSlider", true, false)
	var scan_control := false
	for node in main.hud._psx_panel.find_children("*", "Control", true, false):
		if String(node.get_meta("psx_field", "")) == "scanlines":
			scan_control = true
	_check(not scan_control, "the panel exposes no scanline control")
	var saturation: HSlider = null
	for s in sliders:
		if String(s.get_meta("psx_field", "")) == "saturation":
			saturation = s
	_check(saturation != null, "the panel keeps its remaining screen sliders")
	if saturation != null:
		saturation.value = 1.35
		_check(is_equal_approx(PSXLook.saturation, 1.35),
				"a remaining panel control changes the live manager")
		saturation.value = 1.0
	main._close_psx()
	_check(not main._psx_open and not main.hud.psx_panel_open() and not main._paused,
			"closing the panel resumes play")

	PSXLook.reset_to_defaults(false)
	print("PSX LOOK PASS" if not _failed else "PSX LOOK FAIL")
	if _failed:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
