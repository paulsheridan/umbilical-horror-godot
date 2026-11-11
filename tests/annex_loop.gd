extends Node3D
## Drives the east annex with the real tank controls: the north ring, all four
## corners, the cafeteria arches, and the second mouth back into the junction.
## This is a geometry proof, not a combat test; hosts are deaf and blind here.
##
## Run: godot --headless --path . res://tests/annex_loop.tscn

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
		if to.length() < 0.5:
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
		if drone.global_position.distance_to(last) < 0.01:
			stuck += 1
			if stuck > 90:
				print("    stuck at (%.2f, %.2f) yaw %.2f" % [
					drone.global_position.x, drone.global_position.z, drone.rotation.y])
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
	for _i in 10:
		await get_tree().physics_frame
	main._start_sortie()
	for _i in 10:
		await get_tree().physics_frame
	_check(main.drone != null, "sortie launched for the annex run")
	if main.drone == null:
		print("ANNEX LOOP FAILED")
		get_tree().quit(1)
		return
	# Geometry proof only: keep the M4 stalker out of this drive.
	main._stalk_triggered = true
	for h in main.hosts:
		h.drone = null   # geometry proof only; no pursuit pacing
	# The Collector's bot-carry is a gameplay system, not geometry. Let it
	# keep walking and feeding, but do not let it lift the test chassis.
	main.collector.bots = []

	# Start at the spur mouth, past the dock route already proven by
	# camera_loop. Then drive the donut and cut through the cafeteria.
	main.drone.global_position = Vector3(5.4, 0.32, -29.6)
	main.drone.velocity = Vector3.ZERO
	for _i in 6:
		await get_tree().physics_frame

	var route := [
		Vector3(8.2, 0.0, -29.0),    # south of the wreck
		Vector3(12.0, 0.0, -29.7),   # north ring
		Vector3(18.6, 0.0, -29.7),   # north ring east
		Vector3(20.1, 0.0, -29.7),   # NE corner
		Vector3(20.1, 0.0, -24.0),   # east ring
		Vector3(20.1, 0.0, -18.5),   # east ring
		Vector3(20.1, 0.0, -16.8),   # SE corner
		Vector3(17.0, 0.0, -16.8),   # south ring
		Vector3(12.0, 0.0, -16.8),   # south ring
		Vector3(12.0, 0.0, -18.2),   # cafeteria south arch
		Vector3(10.5, 0.0, -19.2),   # cafeteria south-west lane
		Vector3(7.0, 0.0, -22.0),    # cafeteria west arch
		Vector3(5.4, 0.0, -22.0),    # west ring
		Vector3(5.4, 0.0, -26.0),    # west ring north
		Vector3(2.8, 0.0, -26.2),    # junction, second mouth
	]
	var all_ok := true
	for p in route:
		if main.drone == null:
			all_ok = false
			break
		var ok := await _drive_to(main.drone, p, 700)
		print("  annex waypoint (%.1f, %.1f): %s" % [p.x, p.z, "ok" if ok else "STUCK"])
		if not ok:
			all_ok = false
			break
	_check(all_ok, "drone drives the full donut and cafeteria")

	# The berth wing: back out to the south ring, through the 1.0 m service
	# crawl, down the hall, through a loud cabin door, and back via the east
	# link. This is the drone-only shortcut the Stalker has to route around.
	var wing := [
		Vector3(5.4, 0.0, -22.0),
		Vector3(5.4, 0.0, -17.0),
		Vector3(8.5, 0.0, -16.8),
		Vector3(12.0, 0.0, -16.8),
		Vector3(13.2, 0.0, -16.8),
		Vector3(13.2, 0.0, -11.7),   # through the low crawl
		Vector3(16.0, 0.0, -11.7),
		Vector3(19.8, 0.0, -11.7),
		Vector3(19.8, 0.0, -8.0),    # through the ossuary door
		Vector3(19.8, 0.0, -11.7),
		Vector3(17.6, 0.0, -11.7),
		Vector3(17.6, 0.0, -14.5),   # down the east link
		Vector3(17.6, 0.0, -16.8),
	]
	var wing_ok := true
	for p in wing:
		if main.drone == null:
			wing_ok = false
			break
		var ok := await _drive_to(main.drone, p, 900)
		print("  berth waypoint (%.1f, %.1f): %s" % [p.x, p.z, "ok" if ok else "STUCK"])
		if not ok:
			wing_ok = false
			break
	_check(wing_ok, "drone threads the service crawl and the berth hall")

	if main.drone != null:
		_check(main._visited_zones.has("annex"), "the ring inks on the hand-copy map")
		_check(main._visited_zones.has("cafeteria"), "the cafeteria inks on the hand-copy map")
		_check(main._visited_zones.has("berths"), "the berth wing inks on the hand-copy map")
		_check(main._zone_at(Vector3(12.0, 0, -22.0)) == "cafeteria",
				"cafeteria zone is detected at its centre")
		_check(main._zone_at(Vector3(20.1, 0, -22.0)) == "annex",
				"east ring is detected as annex")
		_check(main._zone_at(Vector3(19.8, 0, -8.0)) == "berths",
				"ossuary zone is detected")

	_stop()
	print("ANNEX LOOP", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
