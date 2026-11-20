extends Node
## Catch close-up probe: when a live-feed chassis is caught, the tube cuts to a
## tight, randomly framed patch of the catcher's face before the snow. The
## camera is staged in world space from the catcher's skull, so it must stay
## outside the head while the feed viewport is still live.
##
## Boot and lifecycle follow `camera_loop.gd`: a real main scene, a real sortie,
## and real actor scenes. Geometry is read back through `main.last_catch_face`,
## which is deliberately kept as plain data for tuning and probes.

var main: Node3D
var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _stop() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")


func _boot() -> void:
	await get_tree().physics_frame
	PSXLook.reset_to_defaults(false)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(5)
	main._on_start_clicked.call_deferred()
	await _wait(12)


## Add a real actor at the drone's elbow. Its own physics is left alone; the
## face beat only needs a valid skull transform.
func _actor(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	var node := scene.instantiate() as Node3D
	main.world.add_child(node)
	await get_tree().physics_frame
	if main.drone != null:
		node.global_position = main.drone.global_position + Vector3(0.7, 0.0, 0.2)
	await _wait(2)
	return node


func _check_face(host: Node3D, label: String, radius: float) -> void:
	var info: Dictionary = main.last_catch_face
	_check(not info.is_empty(), "%s: face staged" % label)
	if info.is_empty():
		return
	var centre: Vector3 = info["head_centre"]
	var head_radius: float = info["head_radius"]
	var cam_pos: Vector3 = info["cam_pos"]
	var face_point: Vector3 = info["face_point"]
	var cam_xform: Transform3D = info["cam_xform"]
	_check(is_equal_approx(head_radius, radius),
			"%s: conservative skull radius %.2f m" % [label, head_radius])
	var dist: float = cam_pos.distance_to(centre)
	_check(dist > head_radius + main._feed_cam.near,
			"%s: camera stays outside the skull (gap %.3f m > near %.3f)" % [
				label, dist - head_radius, main._feed_cam.near])
	_check(dist < head_radius + 0.5,
			"%s: camera is a genuine close-up (%.2f m < %.2f m)" % [
				label, dist, head_radius + 0.5])
	var forward: Vector3 = -cam_xform.basis.z
	var to_face: Vector3 = (face_point - cam_pos).normalized()
	_check(forward.dot(to_face) > 0.9,
			"%s: lens points at the face patch (dot %.2f)" % [label, forward.dot(to_face)])
	_check(info.get("host", null) == host, "%s: pick records its catcher" % label)


func _run() -> void:
	await _boot()

	# Force the live feed, then bind so the HUD's live tube is up before the
	# catch. The staged face needs only a live feed at catch time; the module is
	# permanent kit by now, so its loss can no longer hide the face.
	main._camera_installed = true
	main.debug_vision = false
	main._start_sortie()
	await _wait(12)
	main._bind_active()
	_check(main.drone != null and main._live_feed_active(),
			"live feed is up for the catch probe")
	_check(main.hud._live.visible, "live optics window is already showing")
	_check(main.CATCH_FACE_HOLD >= 0.5 and main.CATCH_FACE_HOLD <= 1.0,
			"face hold is a readable beat under a second (%.2f s)" % main.CATCH_FACE_HOLD)

	# --- Host (zombie) geometry ------------------------------------------------
	var host := await _actor("res://scenes/actors/host.tscn")
	var host_staged: bool = main._stage_catch_face(host)
	_check(host_staged, "host catch face stages")
	_check(main._catch_cam_active, "host face beat is armed")
	_check(main._static_lock == 0.0, "face beat starts with snow suppressed")
	_check_face(host, "host", 0.17)

	# Seeded sampling: the killed patch must not always be the same cheek.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var face_points := {}
	var cam_points := {}
	for _i in 8:
		var pick: Dictionary = main._pick_catch_face(host, rng)
		if pick.is_empty():
			continue
		var fp: Vector3 = pick["face_point"]
		var cp: Vector3 = pick["cam_pos"]
		face_points["%.3f,%.3f,%.3f" % [fp.x, fp.y, fp.z]] = true
		cam_points["%.3f,%.3f,%.3f" % [cp.x, cp.y, cp.z]] = true
	_check(face_points.size() >= 4 or cam_points.size() >= 4,
			"seeded picks frame different face patches (%d face / %d cam distinct)" % [
				face_points.size(), cam_points.size()])

	host.queue_free()
	await _wait(2)

	# --- Watcher geometry: the same zombie rig gets the same close-up -------
	var watcher := await _actor("res://scenes/actors/watcher.tscn")
	_check(main._host_kind(watcher) == "host", "a watcher resolves as the host rig")
	var watcher_staged: bool = main._stage_catch_face(watcher)
	_check(watcher_staged, "watcher catch face stages")
	_check(main._catch_cam_active, "watcher face beat is armed")
	_check(main._static_lock == 0.0, "watcher face beat starts with snow suppressed")
	_check_face(watcher, "watcher", 0.17)
	watcher.queue_free()
	await _wait(2)

	# --- Stalker geometry: centipede rig, face is -Z --------------------------
	var stalker := await _actor("res://scenes/actors/stalker.tscn")
	var stalker_staged: bool = main._stage_catch_face(stalker)
	_check(stalker_staged, "stalker catch face stages")
	_check(main._catch_cam_active, "stalker face beat is armed")
	_check(main._static_lock == 0.0, "stalker face beat starts with snow suppressed")
	_check_face(stalker, "stalker", 0.36)

	# Non-zombies must never get the kill close-up.
	_check(not main._stage_catch_face(main.collector), "collector gets no catch face")
	_check(not main._stage_catch_face(main.processor), "processor gets no catch face")

	# --- Real catch: face hold, then snow, then the chassis is freed -----------
	var caught: Node3D = main.drone
	var catch_pos: Vector3 = caught.global_position
	main._on_drone_caught(stalker)
	var beat_frames := 0
	for _i in 6:
		await get_tree().physics_frame
		beat_frames += 1
		if main._catch_frames >= main.CATCH_FACE_MIN_FRAMES:
			break
	_check(main._catch_cam_active, "face beat still holding after the catch")
	_check(main._catch_frames >= main.CATCH_FACE_MIN_FRAMES,
			"face rendered at least %d frames" % main.CATCH_FACE_MIN_FRAMES)
	_check(main._feed_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"feed viewport renders during the face beat")
	_check(main.hud._live.visible, "live optics are showing the face")
	_check(not main.hud._lens.visible, "black lens is hidden during the face beat")
	_check(not main.hud._feed.visible, "no still photo during the face beat")
	var amt: float = main.hud._static_mat.get_shader_parameter("amount")
	_check(amt < 0.05, "snow is suppressed during the face beat (amount %.3f)" % amt)

	# The attack is still happening: the framing and the dying bot both shudder.
	# Sampling two frames apart guarantees at least one fresh jitter roll.
	var feed_a: Vector3 = main._feed_cam.global_transform.origin
	var drone_a: Vector3 = caught.global_position
	var yaw_a: float = caught.rotation.y
	await _wait(2)
	var feed_b: Vector3 = main._feed_cam.global_transform.origin
	var drone_b: Vector3 = caught.global_position
	var yaw_b: float = caught.rotation.y
	_check(main._catch_cam_active, "face beat still up while sampling the struggle")
	_check(feed_a.distance_to(feed_b) > 0.0005,
			"staged framing shudders during the beat (moved %.4f m)" % [
				feed_a.distance_to(feed_b)])
	_check(drone_a.distance_to(drone_b) > 0.0005 or absf(yaw_a - yaw_b) > 0.0005,
			"caught chassis judders during the beat (moved %.4f m, yaw %.4f rad)" % [
				drone_a.distance_to(drone_b), absf(yaw_a - yaw_b)])
	_check(drone_a.distance_to(drone_b) <= 0.10
			and absf(yaw_a - yaw_b) <= 0.10,
			"the judder stays small (within the named shake constants)")
	_check(drone_b.distance_to(catch_pos) <= 0.2,
			"the death spot holds (chassis %.3f m from the catch point)" % [
				drone_b.distance_to(catch_pos)])

	# The cut arrives after the hold: snow starts and the last frame freezes.
	# Count physics frames from the catch so the beat can be timed: 60 fps, so
	# 18 frames ~ 0.3 s and 72 frames ~ 1.2 s.
	var first_snow := -1
	for _i in 90:
		await get_tree().physics_frame
		beat_frames += 1
		var now: float = main.hud._static_mat.get_shader_parameter("amount")
		if now > 0.2:
			first_snow = beat_frames
			break
	var snow_started := first_snow > 0
	_check(snow_started, "snow takes the tube after the face hold")
	_check(first_snow >= 18,
			"no flash cut: snow had not started by frame %d (0.3 s)" % 18)
	_check(first_snow > 0 and first_snow <= 72,
			"the face holds a beat but under a second (%d frames)" % first_snow)
	_check(GameState.sortie == GameState.Sortie.PILOTING,
			"the cut happens inside the catch window, before teardown")
	_check(not main._catch_cam_active, "face beat has ended")
	_check(main._feed_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"viewport freezes on the last face frame")

	# The 1.6 s window is unchanged: the single-chassis fleet ends the sortie.
	var freed := false
	for _i in 180:
		await get_tree().physics_frame
		if GameState.sortie != GameState.Sortie.PILOTING and main.drone == null:
			freed = true
			break
	_check(freed, "caught chassis is freed and the sortie ends")
	_check(not main._catch_cam_active, "face beat is cleared after teardown")
	_check(main.last_catch_face.is_empty(), "staged face is cleared after teardown")

	# --- Still-only guard: no live feed, no phantom face -----------------------
	main._camera_installed = false
	main.debug_vision = false
	main._start_sortie()
	await _wait(12)
	_check(main.drone != null and not main._live_feed_active(),
			"still-only sortie is up for the guard")
	var guard_host := await _actor("res://scenes/actors/host.tscn")
	main._on_drone_caught(guard_host)
	await _wait(3)
	_check(main.last_catch_face.is_empty(),
			"still-only catch stages no phantom face")
	_check(not main._catch_cam_active,
			"still-only catch leaves the face camera off")

	_stop()
	print("CATCH FACE", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
