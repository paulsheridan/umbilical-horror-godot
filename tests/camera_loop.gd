extends Node
## Hub + camera-module probe: every bay station can be focused, the video
## module can be picked up, brought home, installed at the fabricator, and
## photographed through the still/live optic.
##
## This suite deliberately does not prove a drive route through the level;
## layout changes are covered by playing the game, not by pinning geometry.

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


func _run() -> void:
	await get_tree().physics_frame
	PSXLook.reset_to_defaults(false)
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

	main._start_sortie()
	for _i in 10:
		await get_tree().physics_frame
	for h in main.hosts:
		h.drone = null   # no hunt pacing in this probe
	_check(main.drone != null, "sortie launched")
	if main.drone != null:
		# Pickup event only; the drive route is not part of this probe.
		main.drone.global_position = Vector3(
				main.ship.CAMERA_POS.x, 0.32, main.ship.CAMERA_POS.z)
		main.drone.velocity = Vector3.ZERO
		for _i in 20:
			await get_tree().physics_frame
		var d: float = main.drone.global_position.distance_to(main.ship.CAMERA_POS)
		print("  final drone pos (%.2f, %.2f), distance to module %.2f m, cargo=%s" % [
			main.drone.global_position.x, main.drone.global_position.z, d, main._cargo])
		_check(main._cargo == "camera",
				"camera module picked up at its anchor (d=%.2f m, radius 1.2)" % d)

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
	_check(main.world.get_viewport().get_camera_3d() == main.drone.cam,
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
