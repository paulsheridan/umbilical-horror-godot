extends Node3D
## Focused watcher-AI rules probe. The Watcher watches first and hunts later:
## while passive it closes to its stand-off and plants, and the only loss is a
## contact the player drives into. Once hostile it runs the plain Host brain
## and kills on contact. Everything else is the Host brain it inherits — the
## shared contract lives in tests/host_ai_rules.gd.
##
## Run: godot --headless --path . res://tests/watcher_ai.tscn

const WATCHER_SCENE := preload("res://scenes/actors/watcher.tscn")
const DRONE := preload("res://src/drone/drone.gd")

var watcher: CharacterBody3D
var drone: CharacterBody3D
var _caught := false
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


func _box_body(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	return body


## One live watcher at a time: free the previous body, then spawn a fresh one
## (configured before it enters the tree, the same order main's factory uses).
func _fresh_watcher(aggressive := false) -> void:
	if watcher != null and is_instance_valid(watcher):
		watcher.drone = null
		watcher.queue_free()
		await get_tree().physics_frame
	watcher = WATCHER_SCENE.instantiate()
	if aggressive:
		watcher.configure_aggressive()
	add_child(watcher)
	watcher.global_position = Vector3(0, 0.2, 0)
	watcher.rotation.y = 0.0
	watcher.drone = drone
	watcher.reset()
	watcher.drone_caught.connect(func() -> void: _caught = true)
	_caught = false


func _run() -> void:
	_box_body(Vector3(40, 0.2, 40), Vector3(0, -0.1, 0))

	drone = CharacterBody3D.new()
	drone.set_script(DRONE)
	add_child(drone)
	drone.global_position = Vector3(0, 0.32, -2)

	# --- Unprovoked, it walks its authored route like any host --------------
	await _fresh_watcher()
	watcher.waypoints = [Vector3(-3, 0, 0), Vector3(3, 0, 0)]
	drone.global_position = Vector3(0, 0.32, -30)
	drone.velocity = Vector3.ZERO
	await _wait(150)
	_check(watcher.state == watcher.State.PATROL
			and watcher.global_position.distance_to(Vector3(0, 0.2, 0)) > 0.5,
			"an unprovoked watcher walks its authored route")

	# --- It approaches a visible drone, then plants at the stand-off --------
	await _fresh_watcher()
	watcher.waypoints = []
	drone.global_position = Vector3(0, 0.32, -9.5)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK, "a moving drone is acquired")
	await _wait(240)
	var gap: float = watcher.global_position.distance_to(drone.global_position)
	_check(Vector2(watcher.velocity.x, watcher.velocity.z).length() < 0.15,
			"the watcher plants instead of attacking")
	_check(absf(gap - watcher.WATCH_STANDOFF) < 1.0,
			"it stops at the stand-off (%.1f m)" % gap)
	_check(watcher.state == watcher.State.STALK and watcher._sees,
			"a planted watcher keeps its eyes on the drone")
	_check(watcher._anim_name == "idle", "the planted watcher stands still")
	var face: float = absf(wrapf(watcher.rotation.y
			- watcher._yaw_to(drone.global_position), -PI, PI))
	_check(face < 0.35, "a planted watcher faces the drone it watches")

	# --- It never closes on its own: the stand-off holds indefinitely -------
	var planted_at: Vector3 = watcher.global_position
	await _wait(360)
	_check(not _caught, "a watched drone is never attacked")
	_check(watcher.state == watcher.State.STALK
			and watcher.global_position.distance_to(planted_at) < 0.15,
			"the planted watcher stays planted")

	# --- The player approaches: it does not move ---------------------------
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -2.5)
	await _wait(60)
	_check(watcher.global_position.distance_to(planted_at) < 0.15
			and Vector2(watcher.velocity.x, watcher.velocity.z).length() < 0.15,
			"a watcher does not move when the player approaches")
	_check(watcher.state == watcher.State.STALK and watcher._sees,
			"the approached watcher keeps watching")

	# --- Too close: contact is the fail state ------------------------------
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -0.8)
	await _wait(12)
	_check(_caught, "getting too close is the fail state (contact kills)")

	# --- Losing the drone: the inherited give-up tail -----------------------
	await _fresh_watcher()
	watcher.waypoints = [Vector3(-3, 0, 0), Vector3(3, 0, 0)]
	drone.global_position = Vector3(0, 0.32, -8)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK, "the drone is acquired again")
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _wait(900)
	_check(not _caught, "a lost drone is not caught")
	_check(watcher.state == watcher.State.PATROL,
			"a watcher that loses the drone goes back to patrol")

	# --- The shipped profile: aggressive senses; a parked chassis inside
	#     the still radius is never safe at arm's length.
	await _fresh_watcher(true)
	watcher.waypoints = []
	drone.global_position = Vector3(0, 0.32, -9.5)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(240)
	var agg_gap: float = watcher.global_position.distance_to(drone.global_position)
	_check(absf(agg_gap - watcher.WATCH_STANDOFF) < 1.0,
			"an aggressive watcher still plants at the stand-off (%.1f m)" % agg_gap)
	drone.velocity = Vector3.ZERO
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -3.0)
	await _wait(30)
	_check(watcher.state == watcher.State.STALK and watcher._sees
			and Vector2(watcher.velocity.x, watcher.velocity.z).length() < 0.15,
			"an aggressive watcher sees a parked chassis inside its still radius")
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -0.8)
	await _wait(12)
	_check(_caught, "stopping next to a watcher does not save the chassis")

	# --- The fleet clock's trigger: one sighting per body, counted once -------
	# main arms its shared patience clock from this signal; a second sighting
	# after a give-up must never re-arm it.
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _fresh_watcher()
	watcher.waypoints = [Vector3(-3, 0, 0), Vector3(3, 0, 0)]
	await _wait(2)
	var sights := [0]
	watcher.sighted.connect(func() -> void: sights[0] += 1)
	drone.global_position = Vector3(0, 0.32, -8)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK and sights[0] == 1,
			"the first sighting fires `sighted` once")
	# Break sight through the inherited give-up tail, then sight it again.
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _wait(900)
	_check(watcher.state == watcher.State.PATROL,
			"the watcher gives up the lost drone before the second sighting")
	# It patrols its route facing ±X now, so put the drone back inside its
	# cone rather than assuming the old heading.
	var ahead: Vector3 = -watcher.global_transform.basis.z
	ahead.y = 0.0
	drone.global_position = watcher.global_position + ahead.normalized() * 8.0 \
			+ Vector3(0, 0.12, 0)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK, "the drone is sighted a second time")
	_check(sights[0] == 1, "`sighted` stays one-shot across chases")

	# --- Hostile: it closes inside the stand-off and runs the drone down -----
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _fresh_watcher()
	watcher.waypoints = []
	drone.global_position = Vector3(0, 0.32, -9.5)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK and not watcher.hostile,
			"the watcher is still passive when it acquires the drone")
	watcher.set_hostile(true)
	var min_gap := INF
	for _i in 420:
		await get_tree().physics_frame
		min_gap = minf(min_gap, watcher.global_position.distance_to(drone.global_position))
		if _caught:
			break
	_check(min_gap < watcher.WATCH_STANDOFF,
			"a hostile watcher closes inside the stand-off (%.1f m)" % min_gap)
	_check(_caught, "a hostile watcher kills on contact like the plain host")

	# --- Hostility persists: a give-up does not make it passive again --------
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _fresh_watcher()
	watcher.waypoints = [Vector3(-3, 0, 0), Vector3(3, 0, 0)]
	watcher.set_hostile(true)
	drone.global_position = Vector3(0, 0.32, -8)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.state == watcher.State.STALK, "the hostile watcher acquires the drone")
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -30)
	await _wait(900)
	_check(watcher.hostile and watcher.state == watcher.State.PATROL,
			"a hostile watcher still gives up a trail it lost")
	# Re-sight: hostile closes inside the stand-off instead of planting. Aim it
	# at the drone from its current patrol heading, as a real sighting would.
	var facing: Vector3 = -watcher.global_transform.basis.z
	facing.y = 0.0
	drone.global_position = watcher.global_position + facing.normalized() * 8.0 \
			+ Vector3(0, 0.12, 0)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(6)
	_check(watcher.hostile and watcher.state == watcher.State.STALK,
			"hostility survives the give-up")
	var reclose := watcher.global_position.distance_to(drone.global_position)
	for _i in 300:
		await get_tree().physics_frame
		reclose = watcher.global_position.distance_to(drone.global_position)
		if reclose < watcher.WATCH_STANDOFF - 0.5:
			break
	_check(reclose < watcher.WATCH_STANDOFF,
			"a re-sighted hostile watcher closes again (%.1f m)" % reclose)

	print("WATCHER AI", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
