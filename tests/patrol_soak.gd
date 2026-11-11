extends Node
## Patrol soak — verifies EVERY leg of the patroller's authored loop is
## physically traversable by the actual host body, at 3x time scale.
## Run:  godot --headless --path . res://tests/patrol_soak.tscn
##
## Between-legs the host is placed on the "from" waypoint and pointed at the
## next index. If it reroutes (stuck detector fires), we record a FAIL with
## the position — that is the exact geometry that needs fixing.

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 5:
		await get_tree().physics_frame
	main._on_start_clicked.call_deferred()
	for _i in 5:
		await get_tree().physics_frame
	main._knock_t = 99999.0   # no ambient lures during the soak

	var h = main.hosts[0]
	h.drone = null
	Engine.time_scale = 3.0
	await _soak_host(h, "patroller")
	Engine.time_scale = 1.0
	print("PATROL SOAK", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)


func _soak_host(h, label: String) -> void:
	var wps: Array = h.waypoints
	for i in wps.size():
		var from: Vector3 = wps[i]
		var to_i: int = (i + 1) % wps.size()
		var to: Vector3 = wps[to_i]
		h.state = h.State.PATROL
		h.global_position = from + Vector3(0, 0.2, 0)
		h.velocity = Vector3.ZERO
		h._wp = to_i
		h._rest = 0.0
		h._stuck_run = 0
		var ok := false
		var rerouted := false
		for _f in 500:
			await get_tree().physics_frame
			if h.global_position.distance_to(to) < 0.55:
				ok = true
				break
			if h._wp != to_i:
				rerouted = true
				break
		print("%s %s leg %02d -> %02d (%.1f m)%s" % [
			"PASS" if ok else "FAIL", label, i, to_i,
			Vector2(from.x - to.x, from.z - to.z).length(),
			"" if ok else "  stopped at (%.1f, %.1f)%s" % [
				h.global_position.x, h.global_position.z,
				" [rerouted]" if rerouted else " [timeout]"],
		])
		if not ok:
			_failed = true
