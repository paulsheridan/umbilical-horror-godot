extends CharacterBody3D
## The primary bad guy: the Stalker.
##
## A tall, pale-boned thing that patrols the annex by default. It hears noise
## and investigates the *direction* it came from (never the exact point),
## recognises any player drone on sight, chases it, and kills on contact. If
## the drone breaks line of sight — around a corner or under a low table — it
## remembers the direction it last saw and searches that way.
##
## Hiding: `hide_spots` is a list of {center, half} footprints for low tables.
## A drone inside one is invisible to sight (but not to hearing).
##
## The body is authored in `scenes/actors/stalker.tscn`: a hunched, elongated
## skeleton with a bone skull, ribs, long clawed arms and a low hum. It is
## animated procedurally in `_animate`.

signal drone_caught
signal lunge_started

enum State { PATROL, INVESTIGATE, SEARCH, CHASE, LURK, LUNGE, AMBUSH_SETUP, AMBUSH }

const W_PATROL := 0.85
const W_INVESTIGATE := 1.0
const W_CHASE := 1.35
const W_CHASE_CLOSE := 1.55

const HEARING_MULT := 26.0
const SIGHT_RANGE := 16.0
const SIGHT_FOV := 110.0
## A lit chassis is a beacon: longer eyes, a wider cone, and even low cover no
## longer hides it from sight. This is the flashlight's cost.
const LIGHT_SIGHT_MULT := 1.55
const LIGHT_FOV_MULT := 1.12
const EYE_HEIGHT := 1.75
const CATCH_RANGE := 1.0
const LOSE_SIGHT_TIME := 1.0
const SEARCH_LEAD := 4.0
const SEARCH_TIME := 3.6
const INVESTIGATE_TIMEOUT := 18.0
const ARRIVE := 0.6

## The "don't look back" scare. When the live feed is up and the stalker is
## already behind the drone, it may choose to shadow it at LURK_DIST instead
## of charging. Turning the camera far enough toward it starts the lunge.
const LURK_DIST := 3.2
const W_LURK := 2.2
const LURK_CHANCE := 0.25
const LUNGE_DOT := 0.55       # dot(camera-forward, to-stalker) that reveals it
const LUNGE_RANGE := 6.0
const W_LUNGE := 5.2

## Fold-up ambush: it picks a corner outside the camera, creeps there and
## waits with its face at drone height, eyes shut, until you drive past.
const AMBUSH_CHANCE := 0.30
const AMBUSH_ROLL := 6.0
const AMBUSH_COOLDOWN := 25.0
const AMBUSH_TRIGGER := 3.2
const AMBUSH_WAIT := 22.0
const W_AMBUSH_SETUP := 1.5
## Hunt / hide cycle. It stalks the drone for a while, folds into a wall spot,
## then sets out again — never parked in one corner for the whole session.
const HUNT_DURATION := 16.0


var drone = null
var waypoints: Array = []
var hide_spots: Array = []
var ambush_spots: Array = []
## Low service spaces the body cannot fit through. Each entry has a center,
## half-extents, and two authored routing points on either side. When pursuit
## crosses one, the stalker takes the legal way around instead of wedging.
var chokes: Array = []
## The scanner reads this body as a mass; its noise must not also blip.
var radar_blips := false
## Scales the radar mass while folded up / creeping (main/scanner reads it).
var radar_mass_scale := 1.0
## Set by main while the recovered video module is giving the pilot a live feed.
var feed_active := false
## Debug vision: no sight, no noise response, no catch. Main sets this on its
## developer toggle; the shipped level never spawns this body anyway.
var ghosted := false

var state: int = State.PATROL
## Chase reach, 0..1: the arms come out toward the drone only while closing on
## it. Read by the focused reach probe; the weight keeps the blend smooth.
var arm_reach := 0.0

var _wp := 0
var _rest := 0.0
var _investigate_target := Vector3.ZERO
var _investigate_t := 0.0
var _search_t := 0.0
var _search_yaw := 0.0
var _last_seen_pos := Vector3.ZERO
var _last_seen_dir := Vector3.FORWARD
var _lost_sight_t := 0.0
var _sees := false
var _caught := false
var _commanded := Vector3.ZERO
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _stuck_run := 0
var _gait := 0.0
var _rng := RandomNumberGenerator.new()
var _ambush_target := Vector3.ZERO
var _ambush_roll_t := 8.0
var _ambush_cd := 0.0
var _ambush_t := 0.0
var _ambush_spring := false

## Per-instance ambush tuning. The engine-room Stalker overrides these through
## main so it waits in the machinery instead of roaming the whole floor.
var ambush_chance := AMBUSH_CHANCE
var ambush_roll := AMBUSH_ROLL
var ambush_cooldown := AMBUSH_COOLDOWN
var ambush_wait := AMBUSH_WAIT
var ambush_trigger := AMBUSH_TRIGGER
var hunt_duration := HUNT_DURATION
var _hunt_t := 0.0
## Slow, deliberate patrol; the engine Stalker is tuned down so it prefers the
## lair over covering ground.
var patrol_speed := W_PATROL
## Active way-around route through a choke (see _nav_target).
var _detour: Array = []

# Body rig references, animated in _animate().
var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _eye_l: CSGSphere3D
var _eye_r: CSGSphere3D
var _core: CSGSphere3D
var _hum: AudioStreamPlayer3D = null


func _ready() -> void:
	_rng.randomize()
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")
	floor_snap_length = 0.5
	# The rig is authored in scenes/actors/stalker.tscn.
	_resolve_body()
	# One long sub-bass note. No footsteps: the hum is its whole voice.
	_hum = Sfx.loop3d("stalker_hum", -34.0)
	if _hum != null:
		_hum.position = Vector3(0, 1.3, 0)
		add_child(_hum)
		_hum.play()
	_stuck_last = global_position


func _resolve_body() -> void:
	_rig = $Rig
	_hips = $Rig/Hips
	_torso = $Rig/Hips/Torso
	_head = _torso.get_node("Head")
	_arm_l = _torso.get_node("ArmL")
	_arm_r = _torso.get_node("ArmR")
	_elbow_l = _torso.get_node("ArmL/ElbowL")
	_elbow_r = _torso.get_node("ArmR/ElbowR")
	_leg_l = _hips.get_node("LegL")
	_leg_r = _hips.get_node("LegR")
	_knee_l = _hips.get_node("LegL/KneeL")
	_knee_r = _hips.get_node("LegR/KneeR")
	_eye_l = _torso.get_node("Head/EyeL") as CSGSphere3D
	_eye_r = _torso.get_node("Head/EyeR") as CSGSphere3D
	_core = _torso.get_node("Core") as CSGSphere3D


func reset() -> void:
	state = State.PATROL
	_wp = 0
	_rest = 0.0
	_investigate_t = 0.0
	_search_t = 0.0
	_lost_sight_t = 0.0
	_sees = false
	_caught = false
	_stuck_t = 0.0
	_stuck_run = 0
	_stuck_last = global_position
	_gait = 0.0
	_ambush_roll_t = ambush_roll
	_ambush_cd = 0.0
	_ambush_t = 0.0
	_ambush_spring = false
	radar_mass_scale = 1.0
	arm_reach = 0.0


## Scripted/test entry point: force the chase even if the cone check is noisy.
func force_chase() -> void:
	if drone != null and is_instance_valid(drone):
		_enter_chase()


func _physics_process(delta: float) -> void:
	_sense(delta)
	_ambush_cd = maxf(_ambush_cd - delta, 0.0)
	if state == State.PATROL:
		_ambush_roll_t -= delta
		if _ambush_roll_t <= 0.0:
			_ambush_roll_t = ambush_roll
			if _ambush_cd <= 0.0:
				_try_start_ambush()
	if _caught:
		_halt()
	elif state == State.PATROL:
		_do_patrol(delta)
	elif state == State.INVESTIGATE:
		_do_investigate(delta)
	elif state == State.SEARCH:
		_do_search(delta)
	elif state == State.CHASE:
		_do_chase(delta)
	elif state == State.LURK:
		_do_lurk(delta)
	elif state == State.LUNGE:
		_do_lunge(delta)
	elif state == State.AMBUSH_SETUP:
		_do_ambush_setup(delta)
	elif state == State.AMBUSH:
		_do_ambush(delta)
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	move_and_slide()
	_check_stuck(delta)
	_face(delta)
	_animate(delta)


# --------------------------------------------------------------------------
# Perception
# --------------------------------------------------------------------------

func _sense(delta: float) -> void:
	if ghosted:
		_sees = false
		_caught = false
		if state != State.PATROL:
			_give_up()
		return
	if drone == null or not is_instance_valid(drone):
		_sees = false
		_caught = false
		# An already-folded ambusher keeps waiting when there is no link:
		# the player standing up does not make it abandon its lair.
		if state == State.CHASE or state == State.LURK or state == State.LUNGE \
				or state == State.AMBUSH_SETUP:
			_give_up()
		return

	if state == State.AMBUSH_SETUP:
		_sees = _can_see_drone()
		if _sees and _player_facing_me() and _flat_dist(drone.global_position) < 9.0:
			_enter_chase()
		return
	if state == State.AMBUSH:
		if _drone_near_ambush():
			_enter_lunge(true)
		return
	if state == State.LUNGE:
		return

	_sees = _can_see_drone()
	if _sees:
		_last_seen_pos = drone.global_position
		var v: Vector3 = drone.velocity
		v.y = 0.0
		if v.length() > 0.25:
			_last_seen_dir = v.normalized()
		else:
			var to: Vector3 = drone.global_position - global_position
			to.y = 0.0
			if to.length() > 0.05:
				_last_seen_dir = to.normalized()
		_lost_sight_t = 0.0
		if state != State.CHASE and state != State.LURK and state != State.LUNGE:
			if _try_lurk():
				_enter_lurk()
			else:
				_enter_chase()
	else:
		if state == State.CHASE or state == State.LURK:
			_lost_sight_t += delta
			if _lost_sight_t >= LOSE_SIGHT_TIME:
				# Remember the direction it was last seen heading and search
				# ahead of that, with a little spread.
				var lead: Vector3 = _last_seen_pos + _last_seen_dir * SEARCH_LEAD
				_enter_investigate(_spread_target(lead))
		# A LUNGE is already committed; it keeps going even out of sight.


## The "don't look back" decision. Only while the live feed is up, only when
## the stalker is already behind the drone, and only occasionally: otherwise
## it just chases.
func _try_lurk() -> bool:
	if not feed_active or drone == null or not is_instance_valid(drone):
		return false
	var fwd: Vector3 = -drone.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to_stalker: Vector3 = global_position - drone.global_position
	to_stalker.y = 0.0
	var d := to_stalker.length()
	if d < 2.0 or d > SIGHT_RANGE:
		return false
	if fwd.dot(to_stalker.normalized()) > 0.10:
		return false   # in front of the drone: a normal chase, not a scare
	return _rng.randf() < LURK_CHANCE


func _player_facing_me() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	var fwd: Vector3 = -drone.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to_me: Vector3 = global_position - drone.global_position
	to_me.y = 0.0
	if to_me.length() < 0.1:
		return true
	return fwd.dot(to_me.normalized()) > 0.25


func _drone_near_ambush() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	var flat: Vector3 = global_position - drone.global_position
	flat.y = 0.0
	var d := flat.length()
	if d > ambush_trigger:
		return false
	if d < 0.1:
		return true
	var fwd: Vector3 = -drone.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Do not spring on a drone that has already driven past facing away.
	return fwd.dot(flat.normalized()) > -0.25


## Pick a corner near a wall, outside the drone's view when possible. A forced
## pick (end of a hunt) relaxes the trap rules but always picks a *different*
## corner from the last one, so it never camps a single spot all session.
func _try_start_ambush(force := false) -> bool:
	if drone == null or not is_instance_valid(drone) or ambush_spots.is_empty():
		return false
	var fwd: Vector3 = -drone.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best := Vector3.ZERO
	var best_d := INF
	for p in ambush_spots:
		if force and _ambush_target != Vector3.ZERO \
				and p.distance_to(_ambush_target) < 5.0:
			continue
		var to: Vector3 = p - drone.global_position
		to.y = 0.0
		var d := to.length()
		if not force and (d < 4.0 or d > 14.0):
			continue
		if not force and fwd.dot(to.normalized()) > 0.15:
			continue   # the drone is looking at it; not a trap spot
		if p.distance_to(global_position) > 26.0:
			continue
		if d < best_d:
			best_d = d
			best = p
	if best_d == INF:
		# Fall back to the farthest wall spot from the last hide.
		for p in ambush_spots:
			if _ambush_target != Vector3.ZERO \
					and p.distance_to(_ambush_target) < 5.0:
				continue
			var d: float = global_position.distance_to(p)
			if d < best_d:
				best_d = d
				best = p
	if best_d == INF:
		return false
	if not force and _rng.randf() > ambush_chance:
		return false
	_ambush_target = best
	_ambush_t = 0.0
	_ambush_cd = ambush_cooldown
	state = State.AMBUSH_SETUP
	_halt()
	return true


func _can_see_drone() -> bool:
	if ghosted:
		return false
	if drone == null or not is_instance_valid(drone):
		return false
	var lit := _drone_lit()
	if _drone_hidden() and not lit:
		return false
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var max_range: float = SIGHT_RANGE * (LIGHT_SIGHT_MULT if lit else 1.0)
	if d > max_range:
		return false
	if d < 0.05:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cone: float = SIGHT_FOV * (LIGHT_FOV_MULT if lit else 1.0)
	if fwd.dot(to.normalized()) < cos(deg_to_rad(cone * 0.5)):
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, EYE_HEIGHT, 0),
			drone.global_position + Vector3(0, 0.45, 0))
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


## True while the chassis has its fitted flashlight switched on. Low cover
## hides a dark machine; it does not hide a lit beam.
func _drone_lit() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	return bool(drone.flashlight_installed) and bool(drone.flashlight_on)


## Low tables are true cover: while the drone is under one it is not visible
## to sight. Hearing still works, which is what makes hiding a stillness test.
func _drone_hidden() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	for spot in hide_spots:
		var c: Vector3 = spot["center"]
		var half: Vector2 = spot["half"]
		if absf(drone.global_position.x - c.x) < half.x \
				and absf(drone.global_position.z - c.z) < half.y:
			return true
	return false


func _on_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	if ghosted:
		return
	# Hosts are deaf to each other; source-tagged noise never piles up.
	if source != null:
		if not is_instance_valid(source):
			return
		if source == self or source.is_in_group("hosts"):
			return
	if position.distance_to(global_position) < 1.0:
		return
	var d := position.distance_to(global_position)
	if d > loudness * HEARING_MULT:
		return
	if state == State.CHASE or state == State.LURK or state == State.LUNGE \
			or state == State.AMBUSH_SETUP or state == State.AMBUSH:
		return   # eyes or the set-up scare already own it
	var target := _direction_target(position)
	if state == State.PATROL or state == State.SEARCH:
		_enter_investigate(target)
	elif state == State.INVESTIGATE:
		_investigate_target = target
		_investigate_t = 0.0


## Walk toward the direction a sound came from, not to its exact source.
func _direction_target(pos: Vector3) -> Vector3:
	var flat := pos - global_position
	flat.y = 0.0
	var d := flat.length()
	if d < 0.4:
		return pos
	var dir := flat / d
	var dist := clampf(d * _rng.randf_range(0.55, 0.85), 1.2, d)
	var side := Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(-1.8, 1.8)
	return global_position + dir * dist + side


func _spread_target(pos: Vector3) -> Vector3:
	var flat := pos - global_position
	flat.y = 0.0
	if flat.length() < 0.4:
		return pos
	var dir := flat.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(-1.5, 1.5)
	return pos + side


# --------------------------------------------------------------------------
# States
# --------------------------------------------------------------------------

func _do_patrol(delta: float) -> void:
	if waypoints.is_empty():
		_halt()
		return
	if _rest > 0.0:
		_rest -= delta
		_halt()
		return
	var target: Vector3 = waypoints[_wp]
	_seek(target, patrol_speed)
	if _flat_dist(target) < ARRIVE:
		_wp = (_wp + 1) % waypoints.size()
		_rest = _rng.randf_range(0.7, 1.8)


func _do_investigate(delta: float) -> void:
	_investigate_t += delta
	if _investigate_t > INVESTIGATE_TIMEOUT:
		_enter_search()
		return
	if _flat_dist(_investigate_target) < 0.9:
		_enter_search()
		return
	_seek(_nav_target(_investigate_target), W_INVESTIGATE)


func _do_search(delta: float) -> void:
	_halt()
	_search_t -= delta
	if _search_t <= 0.0:
		_enter_patrol()


func _do_chase(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	_hunt_t += delta
	if _hunt_t >= hunt_duration and _sees:
		_begin_hide()
		return
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d < CATCH_RANGE:
		_catch()
		return
	if _sees:
		var spd := W_CHASE_CLOSE if d > 8.0 else W_CHASE
		_seek(_nav_target(_hunt_target(drone.global_position)), spd)
	else:
		# The grace second: keep moving to the last place it saw motion.
		_seek(_nav_target(_last_seen_pos), W_INVESTIGATE)


## While hunting it prefers the wall line: route through a nearby corner spot
## rather than cutting across the open middle of the room.
func _hunt_target(goal: Vector3) -> Vector3:
	if ambush_spots.is_empty():
		return goal
	var best: Vector3 = goal
	var best_d := INF
	for p in ambush_spots:
		var to_p: float = global_position.distance_to(p)
		if to_p < best_d:
			best_d = to_p
			best = p
	if best_d < 12.0 and best_d < global_position.distance_to(goal):
		return best
	return goal


## Shadow the drone from behind, out of the forward camera. Turning the
## camera far enough toward the stalker starts the lunge.
func _do_lurk(_delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	var fwd: Vector3 = -drone.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to_stalker: Vector3 = global_position - drone.global_position
	to_stalker.y = 0.0
	var d := to_stalker.length()
	if d > 0.1 and d < LUNGE_RANGE \
			and fwd.dot(to_stalker.normalized()) > LUNGE_DOT:
		_enter_lunge()
		return
	var anchor: Vector3 = drone.global_position - fwd * LURK_DIST
	if global_position.distance_to(anchor) > 0.7:
		_seek(anchor, W_LURK)
	else:
		_halt()


func _do_lunge(_delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	if _flat_dist(drone.global_position) < CATCH_RANGE:
		_catch()
		return
	_seek(drone.global_position, W_LUNGE)


func _do_ambush_setup(delta: float) -> void:
	_ambush_t += delta
	if _ambush_t > 12.0:
		_enter_patrol()
		return
	if _flat_dist(_ambush_target) < 0.7:
		_enter_ambush()
		return
	_seek(_ambush_target, W_AMBUSH_SETUP)


func _do_ambush(delta: float) -> void:
	_ambush_t += delta
	_halt()
	if _ambush_t > ambush_wait:
		# With no bound drone it is still waiting in the lair; only break cover
		# when there is something to hunt. This keeps the boot-time ambush read.
		if drone != null and is_instance_valid(drone) \
				and global_position.distance_to(drone.global_position) < 28.0:
			_hunt_t = 0.0
			_last_seen_pos = drone.global_position
			_enter_chase()
		else:
			_ambush_t = ambush_wait * 0.5


## Break off a hunt and fold into a wall spot that is not the previous one.
func _begin_hide() -> void:
	if _try_start_ambush(true):
		return
	_enter_patrol()


# --------------------------------------------------------------------------
# State entry / helpers
# --------------------------------------------------------------------------

func _enter_patrol() -> void:
	state = State.PATROL
	_wp = _nearest_wp()
	_rest = 0.6
	_ambush_spring = false
	_detour.clear()
	radar_mass_scale = 1.0
	_halt()


func _give_up() -> void:
	_caught = false
	_enter_patrol()


func _enter_investigate(target: Vector3) -> void:
	state = State.INVESTIGATE
	_investigate_target = target
	_investigate_t = 0.0
	_search_t = 0.0


func _enter_search() -> void:
	state = State.SEARCH
	_search_t = SEARCH_TIME
	_search_yaw = rotation.y
	_halt()


func _enter_chase() -> void:
	state = State.CHASE
	_lost_sight_t = 0.0
	_hunt_t = 0.0


func _enter_lurk() -> void:
	state = State.LURK
	_lost_sight_t = 0.0
	_halt()


func _enter_lunge(from_ambush := false) -> void:
	if state == State.LUNGE:
		return
	state = State.LUNGE
	_ambush_spring = from_ambush
	_lost_sight_t = 0.0
	radar_mass_scale = 1.0
	lunge_started.emit()


func _enter_ambush() -> void:
	state = State.AMBUSH
	_ambush_t = 0.0
	radar_mass_scale = 0.30
	_halt()
	if _ambush_target == Vector3.ZERO and not ambush_spots.is_empty():
		# The boot-time lair spot is the one nearest the authored spawn.
		var best: Vector3 = ambush_spots[0]
		var best_d := INF
		for p in ambush_spots:
			var d: float = global_position.distance_to(p)
			if d < best_d:
				best_d = d
				best = p
		_ambush_target = best
	if drone != null and is_instance_valid(drone):
		rotation.y = _yaw_to(drone.global_position)


func _catch() -> void:
	if ghosted:
		return
	if _caught:
		return
	_caught = true
	_halt()
	drone_caught.emit()


## The fleet absorbed the loss: a surviving chassis carries the link, so this
## body has not ended the run. Let it return to its own patrol.
func release_catch() -> void:
	_give_up()


func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_commanded = Vector3.ZERO


func _seek(target: Vector3, speed: float) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() > 0.35:
		var dir := flat.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_commanded = Vector3(velocity.x, 0.0, velocity.z)
	else:
		_halt()


## Route around low chokes. If the straight line from here to the target passes
## through a space this body cannot fit into, steer through the authored detour
## points on the other side of it instead. Once the detour is clear, pursuit
## resumes normally.
func _nav_target(target: Vector3) -> Vector3:
	while not _detour.is_empty() and _flat_dist(_detour[0]) < 0.75:
		_detour.pop_front()
	if not _detour.is_empty():
		return _detour[0]
	for c in chokes:
		var center: Vector3 = c["center"]
		var half: Vector2 = c["half"]
		if not _segment_hits_rect(global_position, target, center, half):
			continue
		var north: Vector3 = c["north"]
		var south: Vector3 = c["south"]
		_detour = [north, south] if global_position.z < center.z else [south, north]
		return _detour[0]
	return target


## 2D segment vs axis-aligned rectangle (x/z), used only for choke routing.
func _segment_hits_rect(a: Vector3, b: Vector3, center: Vector3,
		half: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dx := b.x - a.x
	var dz := b.z - a.z
	if absf(dx) < 0.0001:
		if a.x < center.x - half.x or a.x > center.x + half.x:
			return false
	else:
		var ax0 := (center.x - half.x - a.x) / dx
		var ax1 := (center.x + half.x - a.x) / dx
		if ax0 > ax1:
			var tx := ax0
			ax0 = ax1
			ax1 = tx
		t0 = maxf(t0, ax0)
		t1 = minf(t1, ax1)
		if t0 > t1:
			return false
	if absf(dz) < 0.0001:
		if a.z < center.z - half.y or a.z > center.z + half.y:
			return false
	else:
		var az0 := (center.z - half.y - a.z) / dz
		var az1 := (center.z + half.y - a.z) / dz
		if az0 > az1:
			var tz := az0
			az0 = az1
			az1 = tz
		t0 = maxf(t0, az0)
		t1 = minf(t1, az1)
		if t0 > t1:
			return false
	return true


func _flat_dist(target: Vector3) -> float:
	var flat := target - global_position
	flat.y = 0.0
	return flat.length()


func _yaw_to(target: Vector3) -> float:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return rotation.y
	return atan2(-flat.x, -flat.z)


func _nearest_wp() -> int:
	var best := 0
	var best_d := INF
	for i in waypoints.size():
		var d := _flat_dist(waypoints[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _check_stuck(delta: float) -> void:
	if state == State.SEARCH:
		_stuck_t = 0.0
		_stuck_last = global_position
		return
	_stuck_t += delta
	if _stuck_t < 0.6:
		return
	_stuck_t = 0.0
	var moved := global_position.distance_to(_stuck_last)
	_stuck_last = global_position
	if moved < 0.10 and _commanded.length() > 0.2:
		_stuck_run += 1
		if _stuck_run >= 2:
			_stuck_run = 0
			if state == State.PATROL:
				_wp = (_wp + 1) % maxi(waypoints.size(), 1)
			elif state == State.CHASE:
				_enter_investigate(_spread_target(_last_seen_pos + _last_seen_dir * SEARCH_LEAD))
			else:
				_enter_search()
	else:
		_stuck_run = 0


func _face(delta: float) -> void:
	var yaw := rotation.y
	if (state == State.CHASE or state == State.LURK or state == State.LUNGE) \
			and drone != null and is_instance_valid(drone):
		yaw = _yaw_to(drone.global_position if _sees else _last_seen_pos)
	elif velocity.length() > 0.18:
		yaw = atan2(-velocity.x, -velocity.z)
	elif state == State.SEARCH:
		yaw = _search_yaw + sin(Time.get_ticks_msec() / 1000.0 * 0.9) * 0.18
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 4.5, 1.0))


# --------------------------------------------------------------------------
# Body + animation
# --------------------------------------------------------------------------

func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	# The chase reach is a weight, not a clip: it ramps only while the body is
	# actually running the drone down, and fades back into the walk swing.
	var chasing := state == State.CHASE and speed > 0.12
	arm_reach = move_toward(arm_reach, 1.0 if chasing else 0.0, delta / 0.2)
	if state == State.AMBUSH:
		_animate_ambush(delta)
		_update_presence()
		return
	if state == State.LUNGE and _ambush_spring:
		# Keep the face at drone height for the pounce instead of standing up.
		_animate_ambush(delta)
		var k := minf(delta * 9.0, 1.0)
		_head.rotation.x = lerpf(_head.rotation.x, 0.95, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.35, k)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.35, k)
		_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, -0.40, k)
		_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, -0.40, k)
		_update_presence()
		return
	var moving := speed > 0.12
	_gait += delta * (1.6 + speed * 2.2)
	var amp := 0.16 + minf(speed / W_CHASE, 1.0) * 0.42
	var sw := sin(_gait) * amp
	if moving:
		_leg_l.rotation.x = sw
		_leg_r.rotation.x = -sw
		_knee_l.rotation.x = 0.12 + maxf(0.0, -sw) * 1.15
		_knee_r.rotation.x = 0.12 + maxf(0.0, sw) * 1.15
		_arm_l.rotation.x = -sw * 0.8
		_arm_r.rotation.x = sw * 0.8
		_elbow_l.rotation.x = -0.22 - absf(sw) * 0.35
		_elbow_r.rotation.x = -0.22 - absf(sw) * 0.35
		_hips.position.y = 1.05 + absf(sin(_gait)) * 0.045
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, minf(delta * 6.0, 1.0))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, minf(delta * 6.0, 1.0))
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x, 0.12, minf(delta * 6.0, 1.0))
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x, 0.12, minf(delta * 6.0, 1.0))
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.08, minf(delta * 3.0, 1.0))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.08, minf(delta * 3.0, 1.0))
		_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, -0.18, minf(delta * 3.0, 1.0))
		_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, -0.18, minf(delta * 3.0, 1.0))
		_hips.position.y = lerpf(_hips.position.y, 1.05, minf(delta * 4.0, 1.0))

	# Chase: both hands held out at the drone while the legs keep running. The
	# gait tremble keeps the pose from reading as pinned, and the weight hands
	# the arms straight back to the walk/idle swing when the chase ends.
	if arm_reach > 0.001:
		var reach := -1.0 + sin(_gait * 1.6) * 0.10
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, reach, arm_reach)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, reach, arm_reach)
		_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, -0.50, arm_reach)
		_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, -0.50, arm_reach)

	if state == State.LURK or state == State.LUNGE:
		var reach := -1.05 + sin(_gait) * 0.12
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, reach, minf(delta * 8.0, 1.0))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, reach, minf(delta * 8.0, 1.0))
		_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, -0.55, minf(delta * 8.0, 1.0))
		_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, -0.55, minf(delta * 8.0, 1.0))

	var lean := -0.28
	if state == State.CHASE:
		lean -= 0.14
	elif state == State.LURK:
		lean -= 0.10
	elif state == State.LUNGE:
		lean -= 0.34
	_torso.rotation.x = lerpf(_torso.rotation.x, lean, minf(delta * 4.0, 1.0))
	_torso.rotation.z = sin(_gait) * 0.035 + sin(Time.get_ticks_msec() / 1000.0 * 0.7) * 0.012

	var look := 0.0
	if state == State.SEARCH:
		look = sin(Time.get_ticks_msec() / 1000.0 * 1.5) * 0.55
	elif (state == State.CHASE or state == State.LURK or state == State.LUNGE) \
			and drone != null and is_instance_valid(drone):
		look = clampf(wrapf(_yaw_to(drone.global_position) - rotation.y, -PI, PI),
				-0.45, 0.45)
	else:
		look = sin(Time.get_ticks_msec() / 1000.0 * 0.6) * 0.10
	_head.rotation.y = lerp_angle(_head.rotation.y, look, minf(delta * 4.0, 1.0))
	_head.rotation.x = -0.06 + sin(Time.get_ticks_msec() / 1000.0 * 0.8) * 0.03

	_update_presence()


func _animate_ambush(delta: float) -> void:
	var k := minf(delta * 6.0, 1.0)
	_hips.position.y = lerpf(_hips.position.y, 0.56, k)
	_torso.rotation.x = lerpf(_torso.rotation.x, -1.05, k)
	_torso.rotation.z = lerpf(_torso.rotation.z, 0.0, k)
	_head.rotation.x = lerpf(_head.rotation.x, 0.85, k)
	_head.rotation.y = lerpf(_head.rotation.y, 0.0, k)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -1.25, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -1.25, k)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, 2.2, k)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, 2.2, k)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 1.25, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 1.25, k)
	_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, 1.3, k)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, 1.3, k)
	_gait += delta * 0.4


## Eyes, core, radar mass and voice. Folded up / creeping is quiet and nearly
## invisible; the spring opens the eyes wide and restores the full mass.
func _update_presence() -> void:
	var eyes := 1.0
	if state == State.AMBUSH or state == State.AMBUSH_SETUP:
		eyes = 0.01
	elif state == State.LUNGE:
		eyes = 4.0
	if _eye_l != null:
		_eye_l.scale = Vector3.ONE * eyes
	if _eye_r != null:
		_eye_r.scale = Vector3.ONE * eyes
	if _core != null:
		_core.visible = not (state == State.AMBUSH or state == State.AMBUSH_SETUP)

	if state == State.AMBUSH_SETUP:
		radar_mass_scale = 0.70
	elif state == State.AMBUSH:
		radar_mass_scale = 0.30
	elif state == State.LUNGE:
		radar_mass_scale = 1.0
	elif state == State.PATROL or state == State.INVESTIGATE \
			or state == State.SEARCH or state == State.CHASE or state == State.LURK:
		radar_mass_scale = 1.0

	if _hum != null:
		if state == State.AMBUSH or state == State.AMBUSH_SETUP:
			_hum.volume_db = -40.0
			_hum.pitch_scale = 0.58
		else:
			var cam := get_viewport().get_camera_3d()
			var near := 0.0
			if cam != null:
				var d := global_position.distance_to(cam.global_position)
				near = clampf(1.0 - d / 18.0, 0.0, 1.0)
			_hum.volume_db = lerpf(-34.0, -2.0, near * near)
			_hum.pitch_scale = lerpf(0.82, 0.66, near)
