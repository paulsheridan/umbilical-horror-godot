extends Node3D
## Focused host-AI rules probe. Builds a synthetic room + wall so sight,
## line-of-sight loss, stillness safety and stalking distance can be tested
## without depending on the ship's authored geometry.
##
## Run: godot --headless --path . res://tests/host_ai_rules.tscn

const HOST := preload("res://src/host/host.gd")
const DRONE := preload("res://src/drone/drone.gd")

var host: CharacterBody3D
var drone: CharacterBody3D
var wall: StaticBody3D
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


func _run() -> void:
	# Floor + the corner wall. The wall sits between host (z=2) and drone
	# (z=-2) so sight is blocked until we free it.
	_box_body(Vector3(24, 0.2, 24), Vector3(0, -0.1, 0))
	wall = _box_body(Vector3(6, 2.0, 0.3), Vector3(0, 1.0, 0))

	drone = CharacterBody3D.new()
	drone.set_script(DRONE)
	add_child(drone)
	drone.global_position = Vector3(0, 0.32, -2)

	host = CharacterBody3D.new()
	host.set_script(HOST)
	add_child(host)
	host.global_position = Vector3(0, 0.2, 2)
	host.waypoints = [Vector3(0, 0, 2)]
	host.drone = drone
	host.reset()
	host.drone_caught.connect(func() -> void: _caught = true)

	# --- Sight is blocked by the wall: stalk decays into a search -----------
	drone.velocity = Vector3(0, 0, -1)   # movement makes it "visible"
	host.force_stalk(drone.global_position)
	await _wait(10)
	_check(host.state == host.State.STALK, "stalk begins on a blocked sight line")
	await _wait(150)   # > LOSE_SIGHT_TIME
	_check(host.state != host.State.STALK, "lost sight around the wall ends the stalk")
	await _wait(600)   # search + give-up
	_check(host.state == host.State.PATROL, "hidden drone is given up on")

	# --- Freeze is safety: a still drone is unseen at any range --------------
	wall.queue_free()
	await _wait(2)
	host.reset()
	host.rotation.y = 0.0
	host.global_position = Vector3(0, 0.2, 0)
	host.waypoints = []          # no patrol turn: keep the sight test clean
	drone.global_position = Vector3(0, 0.32, -5)
	drone.velocity = Vector3.ZERO
	await _wait(30)
	_check(host.state == host.State.PATROL, "a still drone beyond old close range is unseen")

	# Stillness works even at arm's length: no close-range sight exception.
	drone.global_position = Vector3(0, 0.32, -2.0)
	await _wait(30)
	_check(host.state == host.State.PATROL, "a still drone 2 m away is still unseen")

	# Movement in the open re-acquires it.
	drone.global_position = Vector3(0, 0.32, -5)
	drone.velocity = Vector3(0, 0, -1)
	await _wait(5)
	_check(host.state == host.State.STALK, "moving drone in the open triggers a stalk")

	# --- Stalk keeps its distance instead of beelining ----------------------
	await _wait(120)
	var gap: float = host.global_position.distance_to(drone.global_position)
	_check(host.state == host.State.STALK, "stalk holds while the drone is visible")
	_check(gap > 3.0, "stalk keeps distance (%.1f m)" % gap)

	# --- Stopping breaks sight; it searches instead of catching -------------
	drone.velocity = Vector3.ZERO
	await _wait(420)   # > LOSE_SIGHT_TIME + walk-to-memory
	_check(not _caught, "a drone that stops is not closed on and caught")
	_check(host.state != host.State.STALK, "stopping ends the stalk")

	# --- Frozen inside the old press range is not a catch -------------------
	_caught = false
	host.reset()
	host.rotation.y = 0.0
	host.global_position = Vector3(0, 0.2, 0)
	drone.velocity = Vector3.ZERO
	drone.global_position = host.global_position + Vector3(0, 0.12, -2.2)
	host.force_stalk(drone.global_position)
	await _wait(240)   # long enough to search the spot
	_check(not _caught, "frozen drone inside old press range survives")
	_check(host.state != host.State.STALK, "a frozen drone is dropped from the stalk")

	# --- But contact still kills: if it is on top of you, it has you --------
	_caught = false
	host.reset()
	host.rotation.y = 0.0
	host.global_position = Vector3(0, 0.2, 0)
	drone.velocity = Vector3(0, 0, -1)
	drone.global_position = host.global_position + Vector3(0, 0.12, -0.8)
	host.force_stalk(drone.global_position)
	await _wait(5)
	_check(_caught, "contact inside catch range still kills")
	_check(host.state == host.State.STALK, "catch leaves the host on the body")

	print("HOST AI RULES", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
