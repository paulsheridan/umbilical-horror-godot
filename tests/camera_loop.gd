extends Node
## End-to-end reachability probe: can a player actually drive the drone from
## the dock to the spur wreck, pick up the camera module, bring it home,
## install it at the fabricator, and photograph through the still optic?
##
## This is deliberately a *real drive* (tank controls, no teleports) for the
## outbound leg, because the authored location must be reachable by the
## vehicle the player owns.

var main: Node3D
var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _stop() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")


func _drive_to(drone, target: Vector3, max_frames: int) -> bool:
	# Tank autopilot: turn toward the target, then drive. Used only by tests.
	var stuck := 0
	var last: Vector3 = drone.global_position
	for i in max_frames:
		var to: Vector3 = target - drone.global_position
		to.y = 0.0
		if to.length() < 0.45:
			_stop()
			return true
		var want := atan2(-to.x, -to.z)
		var dy := wrapf(want - drone.rotation.y, -PI, PI)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if dy > 0.10:
			Input.action_press("move_left")
		elif dy < -0.10:
			Input.action_press("move_right")
		if absf(dy) < 0.55:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
		await get_tree().physics_frame
		if i % 60 == 0:
			print("  drive (%d) at (%.2f, %.2f) -> (%.2f, %.2f) yaw=%.2f dy=%.2f" % [
				i, drone.global_position.x, drone.global_position.z,
				target.x, target.z, drone.rotation.y, dy])
		if drone.global_position.distance_to(last) < 0.01:
			stuck += 1
			if stuck > 90:
				_stop()
				return false
		else:
			stuck = 0
			last = drone.global_position
	_stop()
	return false


func _run() -> void:
	await get_tree().physics_frame
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 5:
		await get_tree().physics_frame
	main._on_start_clicked.call_deferred()
	for _i in 12:
		await get_tree().physics_frame

	# --- Hub interactables: every station, not just the chair -----------------
	# The player starts at the chair's end of the bay. Verify each authored
	# station can actually be focused and used by walking up to it.
	var hubs := [
		["pilot chair", Vector3(-3.8, 0.05, -1.6), PI * 0.5, -0.1, main.level.pilot_chair],
		["fabricator", Vector3(3.4, 0.05, -2.0), 0.0, -0.1, main.level.fabricator],
		["map table", Vector3(2.2, 0.05, 0.0), PI * 0.5, -0.38, main.level.map_table],
		["lockers", Vector3(5.3, 0.05, -0.3), -PI * 0.5, 0.0, null],
		["barricade", Vector3(-5.8, 0.05, 1.8), PI * 0.5, -0.05, null],
		["drone hatch", Vector3(-2.0, 0.05, -3.6), 0.0, 0.02, null],
	]
	for hub in hubs:
		main.player.global_position = hub[1]
		main.player.rotation.y = hub[2]
		main.player._pitch = hub[3]
		for _i in 8:
			await get_tree().physics_frame
		var f = main.player.focus
		var name: String = hub[0]
		_check(f != null and (hub[4] == null or f == hub[4]),
				"%s is focusable (got %s)" % [name, "nothing" if f == null else f.prompt])

	var route := [
		Vector3(-2.0, 0.0, -7.0),
		Vector3(-2.1, 0.0, -12.8),
		Vector3(-2.2, 0.0, -15.1),
		Vector3(0.1, 0.0, -15.2),
		Vector3(0.3, 0.0, -20.5),
		Vector3(0.2, 0.0, -25.2),
		Vector3(0.0, 0.0, -27.0),
		Vector3(3.4, 0.0, -29.0),
		Vector3(5.6, 0.0, -29.2),
	]
	main._start_sortie()
	for _i in 10:
		await get_tree().physics_frame
	for h in main.hosts:
		h.drone = null   # geometry proof only; no hunt pacing
	_check(main.drone != null, "sortie launched")
	var arrived := false
	for p in route:
		if main.drone == null:
			break
		var ok := await _drive_to(main.drone, p, 900)
		print("  waypoint (%.1f, %.1f): %s" % [p.x, p.z, "ok" if ok else "STUCK"])
		if not ok:
			break
		arrived = true
	_check(arrived, "drone drives the dock -> junction -> spur route")
	if main.drone != null:
		# Push as far into the spur as the wreck allows: this is the actual
		# pickup approach a player would make.
		await _drive_to(main.drone, Vector3(7.4, 0.0, -29.2), 300)
		# The final 1.5 m of approach is what the pickup radius must cover.
		var d: float = main.drone.global_position.distance_to(main.ship.CAMERA_POS)
		print("  final drone pos (%.2f, %.2f), distance to module %.2f m, cargo=%s" % [
			main.drone.global_position.x, main.drone.global_position.z, d, main._cargo])
		_check(main._cargo == "camera",
				"camera module picked up from the spur (d=%.2f m, radius 1.2)" % d)

	# Bring it home and reel (delivery path itself is covered by autotest).
	if main.drone != null:
		main.drone.global_position = main.ship.dock_pos
		main.drone.velocity = Vector3.ZERO
		for _i in 80:
			await get_tree().physics_frame
		main._try_reel(false)
		for _i in 150:
			await get_tree().physics_frame
	_check(main._camera_held, "camera module delivered to the bay")

	# Install at the fabricator through the real focus/interact path.
	main.player.global_position = Vector3(3.4, 0.05, -2.0)
	main.player.rotation.y = 0.0   # face -Z, toward the fabricator
	main.player._pitch = -0.1
	for _i in 12:
		await get_tree().physics_frame
	_check(main.player.focus == main.level.fabricator, "fabricator is focusable at arm's length")
	main.player._press_interact()
	for _i in 5:
		await get_tree().physics_frame
	_check(main._camera_installed, "camera installed through the fabricator")

	# Install unlocks the live feed: the drone camera becomes the main view.
	main._start_sortie()
	for _i in 10:
		await get_tree().physics_frame
	_check(main._live_feed_active(), "installed module unlocks the live feed")
	_check(get_viewport().get_camera_3d() == main.drone.cam,
			"live drone camera is the current view")
	_check(not main.hud._lens.visible, "live feed has no black lens")
	_check(main.hud._live.visible, "live tube filter is shown")
	_check(main.hud._scanner.visible, "radar inset remains available")
	main._take_photo()
	for _i in 3:
		await get_tree().physics_frame
	_check(main._photo_count == 1, "still frame exposed")
	_check(main.hud._feed.visible, "the print is displayed")

	_stop()
	print("CAMERA LOOP", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
