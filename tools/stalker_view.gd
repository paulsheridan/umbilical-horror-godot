extends Node3D
## Screenshot dev tool: renders the centipede Stalker in its key states and
## writes PNGs to /tmp/opencode/ so a reviewer can actually LOOK at it.
##
## Run (windowed tool, not headless):
##   env -u WAYLAND_DISPLAY DISPLAY=:1 godot --path . --resolution 960x540 \
##       --audio-driver Dummy tools/stalker_view.tscn
##
## STALKER_VIEW_VARIANT names the dark-lair capture (default "pale"); run with
## STALKER_VIEW_VARIANT=shadow to keep the pre-material-fix version.
##
## It builds a bare probe room, spawns a real Stalker and Drone, poses the
## state machine directly, captures each beat and quits.

const OUT_DIR := "/tmp/opencode"
const STALKER_SCENE := preload("res://scenes/actors/stalker.tscn")
const DRONE_SCENE := preload("res://scenes/actors/drone.tscn")

## The beast is authored at `CentipedeRig.BODY_SCALE` (1.5x), so every framing
## distance backs off by the same factor and the captures keep the same
## composition. Keep this in step with that constant.
const SHOT_SCALE := 1.5

## Strong white worklight for the lit captures.
const STRONG_POS := Vector3(6.0, 3.5, -6.0)
## The weak warm lamp that stands in for the drone's lamp in the dark shot.
const LAMP_POS := Vector3(2.0, 1.2, 6.0)

var _cam: Camera3D
var _strong: OmniLight3D
var _lamp: OmniLight3D
var _stalker = null
var _drone = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Deferred so the room, bodies and camera are all inside the tree before
	# the first physics tick runs.
	_run.call_deferred()


func _run() -> void:
	_build_room()
	_spawn()
	await _frames(2)

	# ---- Patrol, mid-room, full light -----------------------------------
	await _frames(90)
	await _shoot("patrol.png")

	# ---- Folded lair, full light ----------------------------------------
	_stalker._enter_ambush()
	await _frames(40)
	await _shoot("lair_lit.png")

	# ---- Folded lair, dark: only the weak amber lamp, ~2 m from the body
	_strong.visible = false
	var body: Vector3 = _stalker.global_position + Vector3(0, 0.2, 0)
	_lamp.global_position = body + Vector3(1.4, 0.9, 1.0)
	await _frames(4)
	await _shoot("lair_dark_%s.png" % _variant())

	# ---- Hunt: PROWL, forelegs raised -----------------------------------
	_strong.visible = true
	_lamp.global_position = LAMP_POS
	_stalker.force_chase()
	await _frames(40)
	await _shoot("hunt.png")

	# ---- Spook: reared up in the PLAY hold, mandibles open --------------
	_stalker.force_chase()
	_stalker._enter_play()
	_stalker._play_phase = _stalker.PLAY_PHASE_HOLD
	for i in 6:
		_stalker._animate(0.1)
	# Low hero angle: the reared graspers need to break the body line.
	await _shoot("spook.png", 0.35, 0.3)

	# ---- PSX-converted material path, back in PATROL --------------------
	var converted: Array = PSXConvert.convert(_stalker, {})
	print("PSX converted %d surfaces on the stalker" % converted.size())
	_stalker._enter_patrol()
	await _wait_moving(90)
	await _shoot("patrol_psx.png")

	var images := DirAccess.get_files_at(OUT_DIR)
	print("Stalker view captured (variant=%s)" % _variant())
	for f in images:
		if f.begins_with("patrol") or f.begins_with("lair_") \
				or f.begins_with("hunt") or f.begins_with("spook"):
			print("  ", f)
	get_tree().quit()


# --------------------------------------------------------------------------
# Scene construction
# --------------------------------------------------------------------------

func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.55)
	env.ambient_light_energy = 0.15
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var floor_box := _box(Vector3(24.0, 0.2, 24.0), Vector3(0.0, -0.1, 0.0),
			Mats.deck())
	floor_box.name = "Floor"
	for w: Array in [
		[Vector3(24.4, 4.0, 0.4), Vector3(0.0, 2.0, -12.0), "WallN"],
		[Vector3(24.4, 4.0, 0.4), Vector3(0.0, 2.0, 12.0), "WallS"],
		[Vector3(0.4, 4.0, 24.4), Vector3(-12.0, 2.0, 0.0), "WallW"],
		[Vector3(0.4, 4.0, 24.4), Vector3(12.0, 2.0, 0.0), "WallE"],
	]:
		var wall := _box(w[0], w[1], Mats.wall())
		wall.name = w[2]

	_strong = OmniLight3D.new()
	_strong.name = "StrongLight"
	_strong.light_color = Color(1.0, 1.0, 1.0)
	_strong.light_energy = 1.6
	_strong.omni_range = 30.0
	_strong.shadow_enabled = true
	_strong.position = STRONG_POS
	add_child(_strong)

	_lamp = OmniLight3D.new()
	_lamp.name = "DroneLamp"
	_lamp.light_color = Color(1.0, 0.62, 0.28)
	_lamp.light_energy = 0.25
	_lamp.omni_range = 5.0
	_lamp.position = LAMP_POS
	add_child(_lamp)

	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.near = 0.05
	_cam.fov = 60.0
	_cam.current = true
	add_child(_cam)


func _box(size: Vector3, pos: Vector3, mat: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = size
	box.position = pos
	box.material = mat
	box.use_collision = true
	add_child(box)
	return box


func _spawn() -> void:
	_drone = DRONE_SCENE.instantiate()
	add_child(_drone)
	_drone.global_position = Vector3(2.0, 0.32, 6.0)

	_stalker = STALKER_SCENE.instantiate()
	add_child(_stalker)
	_stalker.global_position = Vector3(0.0, 0.2, 0.0)
	_stalker.waypoints = [
		Vector3(-4.0, 0.2, -4.0),
		Vector3(4.0, 0.2, -4.0),
		Vector3(4.0, 0.2, 4.0),
		Vector3(-4.0, 0.2, 4.0),
	]
	_stalker.hide_spots = []
	_stalker.ambush_spots = [Vector3(0.0, 0.2, 0.0)]
	# The hunt states need a live drone to resolve their targets.
	_stalker.drone = _drone
	_stalker.reset()


# --------------------------------------------------------------------------
# Capture
# --------------------------------------------------------------------------

## Frame the whole beast in profile from ~3.5 m out at ~1.8 m height, then
## grab the drawn frame. The camera follows the body's current yaw so it stays
## side-on after every state turn, and it flips to whichever flank faces the
## active light (a light behind the body photographs it as a black silhouette).
## All distances carry SHOT_SCALE so a bigger body is framed, not cropped.
func _shoot(file_name: String, cam_rise := 0.8, aim_rise := 0.05) -> void:
	var body: Vector3 = _stalker.global_position + Vector3(0.0, 0.18 * SHOT_SCALE, 0.0)
	var yaw_basis := Basis(Vector3.UP, _stalker.rotation.y)
	var right := yaw_basis.x.normalized()
	var fwd := -yaw_basis.z.normalized()
	var light: OmniLight3D = _strong if _strong.visible else _lamp
	var to_light: Vector3 = light.global_position - body
	to_light.y = 0.0
	if right.dot(to_light) < 0.0:
		right = -right
	_cam.global_position = body + right * 2.3 * SHOT_SCALE \
			+ fwd * 0.9 * SHOT_SCALE + Vector3.UP * cam_rise * SHOT_SCALE
	_cam.look_at(body + Vector3.UP * aim_rise * SHOT_SCALE, Vector3.UP)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := img.save_png(path)
	if err != OK:
		push_error("Stalker view: could not save %s (error %d)" % [path, err])
		return
	print("saved %s  %dx%d  %d bytes" % [path, img.get_width(),
			img.get_height(), FileAccess.get_file_as_bytes(path).size()])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Wait out the post-reset rest, then until the body is actually travelling.
func _wait_moving(limit: int) -> void:
	for i in limit:
		await get_tree().physics_frame
		if Vector2(_stalker.velocity.x, _stalker.velocity.z).length() > 0.3:
			# A few more ticks so the gait is mid-stride, not a first step.
			await _frames(12)
			return


func _variant() -> String:
	var v := OS.get_environment("STALKER_VIEW_VARIANT").strip_edges()
	return v if v != "" else "pale"
