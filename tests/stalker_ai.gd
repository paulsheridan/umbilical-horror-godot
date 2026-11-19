extends Node3D
## Focused rules probe for the rebuilt Stalker: a procedural house-centipede
## with a cat-and-mouse hunt. Builds a bare room (floor, one wall, ceiling),
## drives the AI synchronously with physics disabled, and checks the rig / IK /
## gait, the patrol and the senses, the prowl / play / circle / lunge hunt, the
## wall climb and the folded lair.
##
## Run: godot --headless --path . res://tests/stalker_ai.tscn

const STALKER_SCENE := preload("res://scenes/actors/stalker.tscn")
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


## Direct synchronous locomotion. The AI drivers only ever write `velocity`
## (the real body integrates it in _move_tick), so the probe does the same
## bookkeeping itself instead of running physics frames between calls.
func _drive_step(delta: float) -> void:
	stalker.global_position += Vector3(
			stalker.velocity.x, 0.0, stalker.velocity.z) * delta


## One static slab of the probe room, on the world collision layer.
func _slab(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)


func _run() -> void:
	# Probe room: floor, one wall (room face x = 7.8, top y = 5.0) and a
	# ceiling (underside y = 5.6) so the wall top leaves a 0.6 m vault window.
	_slab(Vector3(40, 0.2, 40), Vector3(0, -0.1, 0))
	_slab(Vector3(0.4, 5.0, 12), Vector3(8, 2.5, 0))
	_slab(Vector3(40, 0.3, 40), Vector3(0, 5.75, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	drone = CharacterBody3D.new()
	drone.set_script(DRONE)
	add_child(drone)
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3.ZERO

	stalker = STALKER_SCENE.instantiate()
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

	# ---- Body -----------------------------------------------------------
	_check(stalker._rig != null and stalker._head != null
			and stalker.get_node_or_null("Rig/Head") != null,
			"stalker has a modelled centipede body")
	_check(stalker._rig.leg_count() == 30, "the body carries thirty IK legs")
	_check(stalker._hum != null, "stalker carries its proximity hum")

	# ---- Inverse kinematics: the analytic solve is exact ---------------
	var ik_ok := true
	for i in [0, 15, 29]:
		var leg = stalker._rig.legs[i]
		var hip: Vector3 = leg.seg.global_transform * leg.anchor
		var target: Vector3 = hip + Vector3(0.3, -0.26, 0.15)
		stalker._rig.leg_reach(i, target)
		if stalker._rig.foot_global(i).distance_to(target) >= 0.03:
			ik_ok = false
	_check(ik_ok, "two-bone IK lands the foot on its target")

	var leg15 = stalker._rig.legs[15]
	var hip15: Vector3 = leg15.seg.global_transform * leg15.anchor
	stalker._rig.leg_reach(15, hip15 + Vector3(0.3, -0.26, 0.15))
	_check(leg15.knee.y > hip15.y + 0.05, "the knee arches above the hip")

	# ---- Gait: planted feet hold still under a still body --------------
	for i in 240:
		stalker._rig.update(0.016, Vector3.UP, 0.0, Vector3(0, 0, -2.0),
				null, 0.26, 0.0, 0.0, 0.0)
	# The gait aims each foot ahead of its home by `lead = vel * 0.14`, so the
	# body takes one last shuffle when the velocity drops and that offset
	# returns to neutral. Let that settle, then measure true stillness.
	for i in 60:
		stalker._rig.update(0.016, Vector3.UP, 0.0, Vector3.ZERO,
				null, 0.26, 0.0, 0.0, 0.0)
	var before: Array = []
	for leg in stalker._rig.legs:
		before.append(leg.planted if leg.has_planted else Vector3.ZERO)
	for i in 30:
		stalker._rig.update(0.016, Vector3.UP, 0.0, Vector3.ZERO,
				null, 0.26, 0.0, 0.0, 0.0)
	var planted := 0
	var held := 0
	for i in stalker._rig.legs.size():
		var leg = stalker._rig.legs[i]
		if not leg.has_planted:
			continue
		planted += 1
		if leg.planted == before[i]:
			held += 1
	_check(planted >= 20 and held >= 6,
			"planted feet stay put while the body is still")

	# ---- Patrol by default ---------------------------------------------
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker._do_patrol(0.016)
	_check(stalker.state == stalker.State.PATROL and stalker._commanded.length() > 0.1,
			"stalker patrols its default route")

	# ---- Hearing: investigate the direction, not the exact point -------
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

	# ---- Sight starts the hunt -----------------------------------------
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 4)
	stalker.rotation.y = 0.0
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3.ZERO
	stalker._sense(0.016)
	_check(stalker.state == stalker.State.PROWL, "sight starts the hunt")

	# ---- Cover: a drone under a low table is invisible -----------------
	stalker.hide_spots = [{"center": Vector3(0, 0, 0), "half": Vector2(2.0, 2.0)}]
	stalker._sense(0.5)
	stalker._sense(0.5)
	_check(stalker.state == stalker.State.INVESTIGATE,
			"breaking sight under cover starts a search")
	var lead: Vector3 = stalker._investigate_target - stalker._last_seen_pos
	lead.y = 0.0
	_check(lead.normalized().dot(stalker._last_seen_dir) > 0.4,
			"search remembers the direction the drone was last seen")

	# ---- Flashlight: a lit chassis is a beacon -------------------------
	drone.set_flashlight(true)
	stalker.hide_spots = []
	drone.global_position = Vector3(0, 0.32, -20.0)
	drone.set_flashlight_enabled(false)
	_check(not stalker._can_see_drone(), "unlit drone beyond base range is unseen")
	drone.set_flashlight_enabled(true)
	_check(stalker._can_see_drone(), "lit drone is seen beyond base range")
	stalker.hide_spots = [{"center": Vector3(0, 0, 0), "half": Vector2(2.0, 2.0)}]
	drone.global_position = Vector3(0, 0.32, 0)
	drone.set_flashlight_enabled(false)
	_check(not stalker._can_see_drone(), "dark drone under low cover stays hidden")
	drone.set_flashlight_enabled(true)
	_check(stalker._can_see_drone(), "the beam defeats low-table cover")
	drone.set_flashlight_enabled(false)

	# ---- Prowl: the cat closes, but keeps its distance -----------------
	stalker.reset()
	stalker.hide_spots = []
	stalker.global_position = Vector3(6, 0.2, 0)
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3.ZERO
	stalker.force_chase()
	for i in 60:
		stalker._sees = true
		stalker._do_prowl(0.016)
		_drive_step(0.016)
	var prowl_d: float = stalker._flat_dist(drone.global_position)
	_check(prowl_d < 5.0, "the prowl closes on still prey")
	_check(prowl_d > 2.6, "the prowl keeps its cat's distance")

	# ---- Patience spends, and the kill approach starts -----------------
	stalker.hunt_duration = 1.0
	for i in 80:
		stalker._sees = true
		stalker._do_prowl(0.016)
		_drive_step(0.016)
	_check(stalker.state == stalker.State.CIRCLE,
			"patience spent commits to the kill approach")
	stalker.hunt_duration = 16.0

	# ---- Play: the cut-off lands ahead of the drone ---------------------
	stalker.reset()
	stalker.global_position = Vector3(2, 0.2, 6)
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3(0, 0, -1.5)
	stalker.force_chase()
	stalker._enter_play()
	var heading := Vector3(0, 0, -1)
	_check((stalker._play_intercept - drone.global_position).dot(heading) > 1.0,
			"the cut-off lands ahead of the drone's path")

	# The spook never catches: the drone may sit inside the body.
	drone.global_position = stalker.global_position + Vector3(0.3, 0.12, 0.0)
	stalker._play_phase = stalker.PLAY_PHASE_HOLD
	stalker._play_hold_dur = 0.05
	stalker._do_play(0.1)
	stalker._play_t = 0.01
	stalker._do_play(0.1)
	_check(not _caught and stalker.state == stalker.State.PROWL,
			"the spook never catches, and hands back to the prowl")

	# ---- The kill approach is semi-circular ----------------------------
	stalker.reset()
	stalker.global_position = Vector3(4, 0.2, 0)
	drone.global_position = Vector3(0, 0.32, 0)
	drone.velocity = Vector3.ZERO
	stalker.force_chase()
	stalker._enter_circle()
	stalker._sees = true
	var _angle0: float = stalker._circle_angle
	var d0: float = stalker._flat_dist(drone.global_position)
	var sweep := 0.0
	var prev := atan2(stalker.global_position.z - drone.global_position.z,
			stalker.global_position.x - drone.global_position.x)
	for i in 400:
		stalker._do_circle(0.016)
		_drive_step(0.016)
		if i % 40 == 39:
			var bearing := atan2(stalker.global_position.z - drone.global_position.z,
					stalker.global_position.x - drone.global_position.x)
			sweep += absf(wrapf(bearing - prev, -PI, PI))
			prev = bearing
	var circle_d: float = stalker._flat_dist(drone.global_position)
	_check(circle_d < d0 * 0.75, "the circle closes on the prey")
	_check(sweep > 1.2, "the approach arcs around, never straight")
	_check(stalker.state == stalker.State.CIRCLE or stalker.state == stalker.State.LUNGE,
			"the circle commits to a strike")

	# ---- Lunge / contact kill ------------------------------------------
	stalker.reset()
	_caught = false
	drone.global_position = stalker.global_position + Vector3(0, 0.12, -0.4)
	stalker.force_chase()
	_lunged = false
	stalker._enter_lunge()
	_check(_lunged, "the strike fires the lunge sting")
	stalker._do_lunge(0.016)
	_check(_caught, "contact kills the drone immediately")

	# An overhead body on the far side of the floor gap cannot reach down.
	stalker.reset()
	_caught = false
	stalker.global_position = Vector3(0, 4.7, 0)
	drone.global_position = Vector3(0, 0.32, 0.2)
	stalker._enter_lunge()
	stalker._do_lunge(0.016)
	_check(not _caught, "an overhead strike cannot catch through the floor gap")

	# ---- Wall climbing -------------------------------------------------
	stalker.reset()
	stalker.global_position = Vector3(6.8, 0.2, 0)
	_check(stalker._try_attach(Vector3(1, 0, 0)) and stalker._on_wall
			and stalker._surf_up.distance_to(Vector3(-1, 0, 0)) < 0.1,
			"it latches the wall ahead")

	# ---- Ground settle: gravity puts the body ON the deck ---------------
	# A fresh reset drops the body from just above the probe floor; the box now
	# spans -0.375..+0.375 around its origin, so it must come to rest hovering
	# 0.375 up — trunk plates clear, feet planted (the rig wants 0.39).
	stalker.reset()
	stalker.global_position = Vector3(0, 0.2, 0)
	for i in 90:
		stalker._move_tick(0.016)
	_check(stalker.is_on_floor()
			and stalker.global_position.y > 0.2 and stalker.global_position.y < 0.55,
			"gravity settles the body onto the deck, hovering clear of it")

	# ---- Cling geometry: clear of the face and lying along it -----------
	stalker.global_position = Vector3(6.8, 0.2, 0)
	var reattached: bool = stalker._try_attach(Vector3(1, 0, 0))
	var space := get_world_3d().direct_space_state
	var margin_q := PhysicsRayQueryParameters3D.create(
			stalker.global_position, stalker.global_position - stalker._surf_up * 2.0)
	margin_q.collision_mask = 1
	var margin_hit: Dictionary = space.intersect_ray(margin_q)
	_check(reattached and not margin_hit.is_empty()
			and stalker.global_position.distance_to(margin_hit["position"]) >= 0.7,
			"the clinging body holds its collision clear of the wall")

	var cling_fwd := Vector3(-sin(stalker.rotation.y), 0.0, -cos(stalker.rotation.y))
	_check(absf(cling_fwd.dot(stalker._surf_up)) < 0.35,
			"it lies flat along the wall, never nose-in")

	stalker._climb_goal = {"kind": "perch", "point": Vector3(6.975, 2.4, 0)}
	for i in 150:
		stalker._climb_tick(0.016)
	_check(stalker.global_position.y > 1.6, "it climbs to the perch")

	# Let the rig re-plant on the real surface state now the body is up there.
	for i in 120:
		stalker._climb_tick(0.016)
		stalker._animate(0.016)
	var on_wall := 0
	for leg in stalker._rig.legs:
		if leg.has_planted and leg.planted.x >= 7.55 and leg.planted.x <= 8.05:
			on_wall += 1
	_check(on_wall >= 10, "its feet plant on the wall face")

	# Vault the wall top onto the ceiling.
	stalker._climb_goal = {"kind": "ceiling", "point": Vector3(0, 5.45, 0)}
	for i in 900:
		stalker._climb_tick(0.016)
		if stalker._surf_up.y < -0.9:
			break
	_check(stalker._surf_up.distance_to(Vector3.DOWN) < 0.1,
			"it pours over the wall top onto the ceiling")

	# Ceiling walk.
	stalker._climb_goal = {"kind": "ceiling", "point": Vector3(0, 4.775, -3.0)}
	var reach_before: float = stalker._flat_dist(Vector3(0, 4.775, -3.0))
	for i in 150:
		stalker._climb_tick(0.016)
	var reach_after: float = stalker._flat_dist(Vector3(0, 4.775, -3.0))
	_check(reach_after < reach_before, "it walks the ceiling plane")

	stalker._detach()
	_check(not stalker._on_wall and stalker._surf_up == Vector3.UP,
			"letting go returns it to the floor frame")

	# Letting go of the ceiling must fall back INSIDE the room: no depenetration
	# ejection through the slab, and a floor landing at deck height.
	var max_y: float = stalker.global_position.y
	for i in 300:
		stalker._move_tick(0.016)
		max_y = maxf(max_y, stalker.global_position.y)
	_check(max_y < 5.75 and stalker.is_on_floor() \
			and stalker.global_position.y < 1.0,
			"letting go off the ceiling drops it back inside the room, never through the roof")

	stalker.reset()
	_check(stalker.state == stalker.State.PATROL, "reset clears the climb and the hunt")

	# ---- The folded lair: boot ambush ----------------------------------
	stalker.reset()
	stalker.ambush_spots = [Vector3(4, 0.2, 0)]
	stalker.global_position = Vector3(4, 0.2, 0)
	stalker._enter_ambush()
	stalker._animate(0.5)
	_check(stalker.state == stalker.State.AMBUSH and stalker.radar_mass_scale < 0.5,
			"the lair holds the body folded and dark")
	_check(stalker._rig.eye_l.scale.x < 0.1, "the folded lair shuts its eyes")
	_check(stalker._hum.volume_db < -35.0, "the folded lair holds its hum")

	# A drive-by springs it.
	drone.global_position = Vector3(2, 0.32, 0)
	drone.rotation.y = -PI * 0.5   # face the waiting body
	_lunged = false
	stalker._sense(0.016)
	_check(stalker.state == stalker.State.LUNGE and _lunged,
			"a drive-by springs the ambush")
	stalker._animate(0.016)
	_check(stalker._rig.eye_l.scale.x > 2.0, "the eyes snap open on the spring")

	print("STALKER AI", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
