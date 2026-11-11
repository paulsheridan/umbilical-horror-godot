extends Node3D
## Focused rules probe for the primary stalker. Builds a bare room, drives the
## AI synchronously (physics disabled) and checks patrol, hearing direction,
## sight, hide-table cover, lost-direction search and contact kill.
##
## Run: godot --headless --path . res://tests/stalker_ai.tscn

const STALKER := preload("res://src/host/stalker.gd")
const DRONE := preload("res://src/drone/drone.gd")

var stalker: CharacterBody3D
var drone: CharacterBody3D
var _caught := false
var _lunged := false
var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _run() -> void:
	# Floor.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)

	drone = CharacterBody3D.new()
	drone.set_script(DRONE)
	add_child(drone)
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3.ZERO

	stalker = CharacterBody3D.new()
	stalker.set_script(STALKER)
	add_child(stalker)
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker.rotation.y = 0.0
	stalker.waypoints = [Vector3(0, 0.2, -4), Vector3(4, 0.2, 4)]
	stalker.hide_spots = []
	stalker.drone = drone
	stalker.drone_caught.connect(func() -> void: _caught = true)
	stalker.lunge_started.connect(func() -> void: _lunged = true)
	stalker.reset()
	stalker._rng.seed = 12345
	stalker.set_physics_process(false)
	await get_tree().physics_frame

	_check(stalker._rig != null and stalker._head != null
			and stalker._arm_l != null and stalker._leg_l != null,
			"stalker has a modelled body")
	_check(stalker._hum != null, "stalker carries its proximity hum")

	# Patrol by default.
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker._do_patrol(0.016)
	_check(stalker.state == stalker.State.PATROL and stalker._commanded.length() > 0.1,
			"stalker patrols its default route")

	# Hearing: investigate the direction, not the exact point.
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker._on_noise(Vector3(4, 1.0, 4), 0.6, null)
	var to_noise: Vector3 = Vector3(4, 0, 4) - stalker.global_position
	to_noise.y = 0.0
	var to_target: Vector3 = stalker._investigate_target - stalker.global_position
	to_target.y = 0.0
	_check(stalker.state == stalker.State.INVESTIGATE, "noise starts an investigation")
	_check(stalker._investigate_target.distance_to(Vector3(4, 1.0, 4)) > 0.4,
			"investigation target is not the exact noise point")
	_check(to_target.normalized().dot(to_noise.normalized()) > 0.2,
			"investigation heads toward the heard direction")

	# Sight: recognises the drone immediately and gives chase.
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker.rotation.y = 0.0
	drone.global_position = Vector3(0, 0.32, 0)
	stalker._sense(0.016)
	_check(stalker.state == stalker.State.CHASE, "sight starts an immediate chase")

	# Cover: a drone under a low table is invisible.
	stalker.hide_spots = [{"center": Vector3(0, 0, 0), "half": Vector2(2.0, 2.0)}]
	stalker._sense(0.5)
	stalker._sense(0.5)
	_check(stalker.state == stalker.State.INVESTIGATE,
			"breaking sight under cover starts a search")
	var lead: Vector3 = stalker._investigate_target - stalker._last_seen_pos
	lead.y = 0.0
	_check(lead.normalized().dot(stalker._last_seen_dir) > 0.4,
			"search remembers the direction the drone was last seen")

	# Lurk / don't-look-back scare: only behind the drone and only on live feed.
	stalker.reset()
	drone.global_position = Vector3(0, 0.32, 0)
	drone.rotation.y = 0.0
	stalker.global_position = Vector3(0, 0.2, 3.2)
	stalker.feed_active = false
	_check(not stalker._try_lurk(), "no lurk without the live feed")
	stalker.global_position = Vector3(0, 0.2, -3.2)
	stalker.feed_active = true
	_check(not stalker._try_lurk(), "no lurk from the drone's front")
	stalker.global_position = Vector3(0, 0.2, 3.2)
	stalker._enter_lurk()
	_check(stalker.state == stalker.State.LURK, "live feed behind the drone starts a lurk")
	_lunged = false
	stalker._do_lurk(0.016)
	_check(stalker.state == stalker.State.LURK, "lurk holds while the drone faces away")
	drone.rotation.y = PI
	stalker._do_lurk(0.016)
	_check(stalker.state == stalker.State.LUNGE and _lunged,
			"turning around triggers the jumpscare lunge")

	# Fold-up ambush: low, eyes shut, quiet, then a drive-by spring.
	stalker.reset()
	stalker.ambush_spots = [Vector3(4, 0.2, 0)]
	stalker.global_position = Vector3(4, 0.2, 0)
	stalker._enter_ambush()
	stalker._animate(0.5)
	_check(stalker.state == stalker.State.AMBUSH, "ambush folds the body into a corner")
	_check(stalker._hips.position.y < 0.8, "ambush body crumples low")
	_check(stalker._eye_l.scale.x < 0.1, "eyes are shut in ambush")
	_check(stalker.radar_mass_scale < 0.5, "ambush mass is faint")
	_check(stalker._hum.volume_db < -35.0, "ambush holds the hum")
	_lunged = false
	drone.global_position = Vector3(2, 0.32, 0)
	drone.rotation.y = -PI * 0.5   # face the waiting stalker
	stalker._sense(0.016)
	stalker._animate(0.016)
	_check(stalker.state == stalker.State.LUNGE and _lunged,
			"a drive-by springs the ambush")
	_check(stalker._eye_l.scale.x > 2.0, "eyes snap open big on the spring")

	# Contact kills immediately.
	_caught = false
	stalker.hide_spots = []
	drone.global_position = stalker.global_position + Vector3(0, 0.12, -0.4)
	stalker.force_chase()
	stalker._do_chase(0.016)
	_check(_caught, "contact kills the drone immediately")

	print("STALKER AI", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
