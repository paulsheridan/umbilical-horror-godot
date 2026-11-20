extends "res://src/host/host_base.gd"
## Deck C's tenant: the Stalker, a house-centipede monstrosity.
##
## Design intent — the cat playing with the mouse. Once it SEES a drone it
## hunts for as long as it keeps line of sight, but it does not simply run the
## prey down. First it *plays*: it shadows the drone at a distance, weaving
## behind and beside it, and every so often sprints ahead to cut it off and
## spook it (it deliberately does NOT catch during play — the drone can drive
## right through the body). Only when its patience runs out does it decide to
## kill, and the kill approach is made of shrinking SEMI-CIRCLES, never a
## straight line, until the final committed lunge.
##
## The body is a 30-legged procedural centipede (`CentipedeRig`), built at
## runtime under `Rig`. It walks floors, scales walls and can cling to the
## ceiling: the rig carries the surface orientation while this body keeps its
## yaw-only CharacterBody3D transform.
##
## State machine:
##   PATROL      — crawl the waypoint loop; occasional folded lair re-sit
##   INVESTIGATE — walk toward the *direction* a noise came from
##   SEARCH      — paused sweep where the hunt lost the trail
##   PROWL       — the hunt-follow: shadow the drone at a weaving distance
##   PLAY        — the spook: sprint to an intercept, rear up, skitter away
##   CIRCLE      — the kill approach: shrinking semi-circles round the prey
##   LUNGE       — the strike (the only state that can catch)
##   AMBUSH_SETUP/AMBUSH — crawl to a lair corner and wait, folded, eyes shut

## Emitted once per lunge. Main binds it to the jumpscare sting.
signal lunge_started
## Emitted on the first contact with a sound chassis: it is hurt, not taken.
signal drone_struck

enum State { PATROL, INVESTIGATE, SEARCH, PROWL, PLAY, CIRCLE, LUNGE, AMBUSH_SETUP, AMBUSH }

## The rig's size dial, re-exported so this body's own derived distances grow
## with the monster: clearance, reach, stick and settle heights are all written
## at 1.0 scale against it. Behaviour (speeds, senses, timings) does not scale.
const BODY_SCALE := CentipedeRig.BODY_SCALE

const W_PATROL := 0.85
const W_INVESTIGATE := 1.0
const W_PROWL := 2.4
const W_PROWL_CLOSE := 2.9
const W_PLAY := 4.6
const W_CIRCLE := 3.2
const W_LUNGE := 5.2
const W_AMBUSH_SETUP := 1.5

## Its own authored hearing reach, assigned to the shared hearing_mult var in
## _ready(). The base's 20.0 is the Host's default.
const HEARING_MULT := 26.0
const SIGHT_RANGE := 16.0
const SIGHT_FOV := 110.0
## A lit chassis is a beacon: longer eyes, a wider cone, and even low cover no
## longer hides it from sight. This is the flashlight's cost.
const LIGHT_SIGHT_MULT := 1.55
const LIGHT_FOV_MULT := 1.12
const LOSE_SIGHT_TIME := 1.0
const SEARCH_LEAD := 4.0
const SEARCH_TIME := 3.6
const INVESTIGATE_TIMEOUT := 18.0
const ARRIVE := 0.6

## The kill gate. Only LUNGE may ever call _catch(), and only inside these
## bounds: the body must be on the drone's level, not up a wall. The taller
## lunge arc still stays well under the 2.4 m perch heights, so a wall-cling
## can never reach down and catch.
const CATCH_RANGE := 0.75 * BODY_SCALE
const CATCH_MAX_Y := 1.3

## Prowl orbit: hold this far off the drone, weaving behind/beside it. Frozen
## prey is crept up on, down to the closer floor.
const PROWL_DIST := 4.6
const PROWL_STILL_MIN := 3.2
const PROWL_CREEP := 0.15
const PROWL_FLINCH := 1.2 * BODY_SCALE

## Play pacing. Long patience, then a cut-off sprint and a rear-up spook.
const PLAY_COOLDOWN_BASE := 11.0
const PLAY_CHANCE := 0.55
const PLAY_INIT_MIN := 6.0
const PLAY_INIT_MAX := 10.0
const PLAY_HOLD_MIN := 1.0
const PLAY_HOLD_MAX := 2.2
const PLAY_SPOOK_MIN := 3.0
const PLAY_SPOOK_MAX := 14.0
const PLAY_SKITTER_MIN := 0.6
const PLAY_SKITTER_MAX := 1.0
const PLAY_SKITTER_RUN := 3.5
const PLAY_PHASE_RUSH := 0
const PLAY_PHASE_HOLD := 1
const PLAY_PHASE_SKITTER := 2

## The kill approach. The radius closes in a sawtooth (one arc, then a beat to
## re-adjust) and the body never approaches in a straight line.
const STRIKE_RADIUS := 1.7 * BODY_SCALE
const CIRCLE_RATE := 1.15
const CIRCLE_CLOSE_RATE := 0.55
const CIRCLE_SHRINK_WINDOW := 1.4
const CIRCLE_HOLD_WINDOW := 0.8
const CIRCLE_TIMEOUT := 12.0

## Wall work: the spook can scale the wall ahead of the drone and cling at eye
## height, and the body can vault a wall top onto the ceiling.
const CLIMB_SPEED := 1.6
## Hold-off from the surface, scaled with the body. Tangent-aligned, the box's
## extent along the surface normal is its half-width (0.675) on a wall and its
## half-height (0.375) on the ceiling, so this leaves 0.15 / 0.45 of air behind
## the body in every orientation.
const CLIMB_CLEARANCE := 0.55 * BODY_SCALE
const CLIMB_PLANE_ARRIVE := 0.5
const CLIMB_BLOCK_LIMIT := 2.2

## Fold-up ambush: it picks a corner outside the camera, creeps there and
## waits with its face at drone height, eyes shut, until you drive past.
const AMBUSH_CHANCE := 0.30
const AMBUSH_ROLL := 6.0
const AMBUSH_COOLDOWN := 25.0
const AMBUSH_TRIGGER := 3.2 * BODY_SCALE
const AMBUSH_WAIT := 22.0
## Hunt / hide cycle. It stalks the drone for a while, folds into a wall spot,
## then sets out again — never parked in one corner for the whole session.
const HUNT_DURATION := 16.0

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

## Hunt / strike pose weight, 0..1, smoothed. Feed straight to the rig as its
## `hunt` argument: the forelegs lift and the mandibles open.
var arm_reach := 0.0

var _investigate_target := Vector3.ZERO
var _investigate_t := 0.0
var _search_t := 0.0
var _search_yaw := 0.0
var _last_seen_dir := Vector3.FORWARD
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
## Slow, deliberate patrol; the engine Stalker is tuned down so it prefers the
## lair over covering ground.
var patrol_speed := W_PATROL
## Active way-around route through a choke (see _nav_target).
var _detour: Array = []

# ---- Hunt pacing --------------------------------------------------------
## Seconds of patience spent playing. Loud noise feeds it; LOS does not.
var _kill_t := 0.0
var _play_cd := 6.0
var _play_roll_t := 1.0

# ---- Prowl weave --------------------------------------------------------
var _prowl_still_t := 0.0
var _orbit_bias := 0.5
var _orbit_mag := 0.7
var _orbit_sign := 1.0
var _orbit_flip_t := 3.0

# ---- Play ---------------------------------------------------------------
var _play_phase := PLAY_PHASE_RUSH
var _play_t := 0.0
var _play_hold_dur := 1.4
var _play_recalc_t := 0.0
var _play_intercept := Vector3.ZERO
var _play_head := Vector3.FORWARD
var _play_skitter_target := Vector3.ZERO

# ---- Circle -------------------------------------------------------------
var _circle_t := 0.0
var _circle_radius := 4.0
var _circle_angle := 0.0
var _circle_dir := 1.0
var _circle_flip_t := 3.0
var _circle_shrink_t := CIRCLE_SHRINK_WINDOW
var _circle_hold_t := 0.0

# ---- Lunge --------------------------------------------------------------
var _lunge_miss_t := 0.0
var _lunge_dir := Vector3.FORWARD

# ---- Climb controller ---------------------------------------------------
var _on_wall := false
var _surf_up := Vector3.UP
var _climb_vel := Vector3.ZERO
var _climb_goal: Dictionary = {}
var _climb_blocked_t := 0.0

# ---- Presentation -------------------------------------------------------
var _rig: CentipedeRig
var _head: Node3D
var _skitter_t := 0.0


func _ready() -> void:
	_body_ready()
	# This body's own tuned ears and its shorter self-echo radius; the base
	# holds the shared defaults (the Host's 20.0 / 1.2).
	hearing_mult = HEARING_MULT
	_noise_self_radius = 1.0
	# The centipede is built procedurally; the scene is only the body.
	_rig = CentipedeRig.new()
	_rig.build(self)
	_head = _rig.head
	# One long sub-bass note. No footsteps: the hum is its whole voice.
	_hum = Sfx.loop3d("stalker_hum", -34.0)
	if _hum != null:
		_hum.position = Vector3(0, 0.6, -0.5) * BODY_SCALE
		add_child(_hum)
		_hum.play()
	_stuck_last = global_position


func reset() -> void:
	state = State.PATROL
	_wp = _nearest_wp()
	_rest = 0.0
	_investigate_t = 0.0
	_search_t = 0.0
	_lost_sight_t = 0.0
	_sees = false
	_caught = false
	_stuck_t = 0.0
	_stuck_run = 0
	_stuck_last = global_position
	_ambush_roll_t = ambush_roll
	_ambush_cd = 0.0
	_ambush_t = 0.0
	_ambush_spring = false
	_detour.clear()
	radar_mass_scale = 1.0
	arm_reach = 0.0
	# Hunt pacing.
	_kill_t = 0.0
	_play_cd = _rng.randf_range(PLAY_INIT_MIN, PLAY_INIT_MAX)
	_play_roll_t = 1.0
	_play_phase = PLAY_PHASE_RUSH
	_play_t = 0.0
	_play_recalc_t = 0.0
	_play_intercept = global_position
	_play_skitter_target = global_position
	# Prowl weave.
	_prowl_still_t = 0.0
	_orbit_bias = 0.5
	_orbit_mag = 0.7
	_orbit_sign = 1.0
	_orbit_flip_t = 3.0
	# Circle.
	_circle_t = 0.0
	_circle_radius = 4.0
	_circle_angle = 0.0
	_circle_dir = 1.0
	_circle_flip_t = 3.0
	_circle_shrink_t = CIRCLE_SHRINK_WINDOW
	_circle_hold_t = 0.0
	# Lunge.
	_lunge_miss_t = 0.0
	_lunge_dir = Vector3.FORWARD
	# Climb.
	_on_wall = false
	_surf_up = Vector3.UP
	_climb_goal.clear()
	_climb_vel = Vector3.ZERO
	_climb_blocked_t = 0.0
	velocity = Vector3.ZERO
	_skitter_t = 0.0


## Scripted/test entry point: force the hunt even if the cone check is noisy.
## It is the PROWL now: the cat starts playing with the mouse.
func force_chase() -> void:
	if drone == null or not is_instance_valid(drone):
		return
	_sees = true
	_remember_drone()
	_enter_prowl()


func _physics_process(delta: float) -> void:
	# ESC pause freezes the drone; a stalking body must freeze with it or the
	# pause veil becomes a free kill.
	if GameState.paused:
		return
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
	elif state == State.PROWL:
		_do_prowl(delta)
	elif state == State.PLAY:
		_do_play(delta)
	elif state == State.CIRCLE:
		_do_circle(delta)
	elif state == State.LUNGE:
		_do_lunge(delta)
	elif state == State.AMBUSH_SETUP:
		_do_ambush_setup(delta)
	elif state == State.AMBUSH:
		_do_ambush(delta)
	_move_tick(delta)
	if _on_wall:
		_climb_tick(delta)
	else:
		_check_stuck(delta)
	_face(delta)
	_animate(delta)


# --------------------------------------------------------------------------
# Perception
# --------------------------------------------------------------------------

func _sense(delta: float) -> void:
	_unlatch_spurned_catch()
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
		if state == State.PROWL or state == State.PLAY or state == State.CIRCLE \
				or state == State.AMBUSH_SETUP:
			_give_up()
		return

	if state == State.AMBUSH_SETUP:
		_sees = _can_see_drone()
		if _sees and _player_facing_me() and _flat_dist(drone.global_position) < 9.0:
			_remember_drone()
			_enter_prowl()
		return
	if state == State.AMBUSH:
		if _drone_near_ambush():
			_enter_lunge(true)
		return
	if state == State.LUNGE:
		return

	_sees = _can_see_drone()
	if _sees:
		_remember_drone()
		if state == State.PATROL or state == State.INVESTIGATE \
				or state == State.SEARCH:
			_enter_prowl()
	else:
		if state == State.PROWL or state == State.PLAY or state == State.CIRCLE:
			_lost_sight_t += delta
			if _lost_sight_t >= LOSE_SIGHT_TIME:
				# Remember the direction it was last seen heading and search
				# ahead of that, with a little spread.
				var lead: Vector3 = _last_seen_pos + _last_seen_dir * SEARCH_LEAD
				_enter_investigate(_spread_target(lead))
		# A LUNGE is already committed; it keeps going even out of sight.


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
		# Fall back to the nearest wall spot to this body (never the last hide).
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
	# The eyes are on the head, so the ray starts where the head actually is
	# (it sways and dips with the rig) rather than at a fixed eye height.
	var origin := global_position + Vector3(0, 0.55, 0)
	if _head != null:
		origin = _head.global_position + Vector3(0, 0.05, 0)
	var q := PhysicsRayQueryParameters3D.create(
			origin, drone.global_position + Vector3(0, 0.45, 0))
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


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
	if not _noise_audible(position, loudness, source):
		return
	if state == State.PROWL:
		# A bang makes the cat stop playing: loud noise shortens its patience
		# without revealing anything it did not already see.
		_kill_t += loudness * 2.0
		return
	if state == State.PLAY or state == State.CIRCLE or state == State.LUNGE \
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
# States: patrol / investigate / search
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


# --------------------------------------------------------------------------
# States: prowl / play / circle / lunge
# --------------------------------------------------------------------------

## The hunt-follow. Shadow the drone at a weaving distance, rise to the kill
## only once patience is spent. Catching is impossible here: the body is
## following, not striking.
func _do_prowl(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	var d := _flat_dist(drone.global_position)
	_kill_t += delta
	if _kill_t >= hunt_duration and _sees:
		_enter_circle()
		return

	# The drone ramming the body: the cat flinches off rather than biting.
	if d < PROWL_FLINCH:
		var away: Vector3 = global_position - drone.global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3.FORWARD
		_seek(global_position + away.normalized() * 2.0, W_PLAY)
		return

	# Play roll: every second, when the cooldown is up, maybe cut it off.
	_play_cd = maxf(_play_cd - delta, 0.0)
	_play_roll_t -= delta
	if _play_roll_t <= 0.0:
		_play_roll_t = 1.0
		if _play_cd <= 0.0 and d >= PLAY_SPOOK_MIN and d <= PLAY_SPOOK_MAX:
			var chance: float = PLAY_CHANCE * (1.5 if feed_active else 1.0)
			if _rng.randf() < chance:
				_enter_play()
				return

	# Frozen prey is crept up on; moving prey is held at a distance.
	var still := Vector2(drone.velocity.x, drone.velocity.z).length() < 0.25
	if still:
		_prowl_still_t = minf(_prowl_still_t + delta, 60.0)
	else:
		_prowl_still_t = maxf(_prowl_still_t - delta * 2.0, 0.0)
	var hold := clampf(PROWL_DIST - _prowl_still_t * PROWL_CREEP,
			PROWL_STILL_MIN, PROWL_DIST)

	# Weave: the bias eases toward the current side rather than snapping.
	_orbit_flip_t -= delta
	if _orbit_flip_t <= 0.0:
		_orbit_sign = -_orbit_sign
		_orbit_mag = _rng.randf_range(0.5, 0.9)
		_orbit_flip_t = _rng.randf_range(3.0, 6.0)
	_orbit_bias = move_toward(_orbit_bias, _orbit_sign * _orbit_mag, 1.2 * delta)

	var drone_pos: Vector3 = drone.global_position
	if d > hold + 1.5:
		_seek(_nav_target(drone_pos), W_PROWL_CLOSE)
		return
	if d < hold - 1.5:
		var away: Vector3 = global_position - drone_pos
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3.FORWARD
		_seek(global_position + away.normalized() * 2.5, W_PROWL)
		return
	# Strafe: sit on a bearing that is NOT the drone's tail, biased off it.
	var to_me: Vector3 = global_position - drone_pos
	to_me.y = 0.0
	var bearing := 0.0
	if to_me.length() > 0.05:
		bearing = atan2(to_me.z, to_me.x)
	var orbit := Vector3(cos(bearing + _orbit_bias), 0.0,
			sin(bearing + _orbit_bias)) * hold
	_seek(_nav_target(drone_pos + orbit), W_PROWL)


## The spook. Sprint to where the drone is going, rear up in its path, then
## skitter off. Never catches: the drone can drive right through it.
func _do_play(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	if _play_phase == PLAY_PHASE_RUSH:
		_play_recalc_t -= delta
		if _play_recalc_t <= 0.0:
			_play_recalc_t = 0.5
			var heading := _drone_heading()
			if heading.dot(_play_head) < 0.96:
				_compute_intercept()
		var d_drone := _flat_dist(drone.global_position)
		var to_i: Vector3 = _play_intercept - global_position
		to_i.y = 0.0
		if to_i.length() < 0.8 or d_drone < 1.6:
			_begin_hold()
			return
		_seek(_play_intercept, W_PLAY)
		return

	if _play_phase == PLAY_PHASE_HOLD:
		_halt()
		_play_t += delta
		if _play_t >= _play_hold_dur or _flat_dist(drone.global_position) < 1.3:
			if _on_wall:
				_detach()
			_begin_skitter()
		return

	# SKITTER
	_play_t -= delta
	_seek(_play_skitter_target, W_PLAY)
	if _play_t <= 0.0:
		_enter_prowl(true)


func _compute_intercept() -> void:
	if drone == null or not is_instance_valid(drone):
		return
	var drone_pos: Vector3 = drone.global_position
	var d := _flat_dist(drone_pos)
	var heading := _drone_heading()
	_play_head = heading
	var prey_speed := Vector2(drone.velocity.x, drone.velocity.z).length()
	var t := clampf(d / maxf(W_PLAY - prey_speed, 0.8), 0.9, 3.2)
	var flat_pos := Vector3(drone_pos.x, global_position.y, drone_pos.z)
	_play_intercept = flat_pos + heading * t


func _begin_hold() -> void:
	_play_phase = PLAY_PHASE_HOLD
	_play_t = 0.0
	_play_hold_dur = _rng.randf_range(PLAY_HOLD_MIN, PLAY_HOLD_MAX)
	# The screech and the rear-up are the whole point of the beat.
	Sfx.play("screech", global_position, -4.0, 1.35)
	_wall_flavor()


## Sometimes the spook happens on a wall: scale the surface ahead of the drone
## and cling there at eye height, facing it. Failure keeps the body on the
## floor (the beat still lands, just lower down).
func _wall_flavor() -> void:
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = _play_intercept + Vector3(0, 0.6 * BODY_SCALE, 0)
	var best_d := INF
	var best_hit: Dictionary = {}
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 2.4)
		q.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var d: float = origin.distance_to(hit["position"])
		if d < best_d:
			best_d = d
			best_hit = hit
	if best_hit.is_empty():
		return
	var normal: Vector3 = best_hit["normal"]
	if absf(normal.y) >= 0.35:
		return
	if _rng.randf() >= 0.5:
		return
	if not _try_attach(-normal):
		return
	var wall_point: Vector3 = best_hit["position"]
	_climb_goal = {
		"kind": "perch",
		"point": wall_point + normal * CLIMB_CLEARANCE \
				+ Vector3.UP * _rng.randf_range(1.4, 2.4),
	}


func _begin_skitter() -> void:
	_play_phase = PLAY_PHASE_SKITTER
	_play_t = _rng.randf_range(PLAY_SKITTER_MIN, PLAY_SKITTER_MAX)
	var heading := _drone_heading()
	var perp := Vector3(-heading.z, 0.0, heading.x)
	# Dash to the roomier side: the side facing away from the nearest wall.
	var side := 1.0
	if _wall_gap(perp) < PLAY_SKITTER_RUN and _wall_gap(-perp) > _wall_gap(perp):
		side = -1.0
	_play_skitter_target = global_position + perp * side * PLAY_SKITTER_RUN


## Free flat distance along `dir` before geometry (used to pick a dash side).
func _wall_gap(dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.45 * BODY_SCALE, 0)
	var q := PhysicsRayQueryParameters3D.create(from,
			from + dir.normalized() * PLAY_SKITTER_RUN)
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return PLAY_SKITTER_RUN
	return from.distance_to(hit["position"])


## The kill approach: shrinking semi-circles. It arcs round the prey, pauses
## to re-adjust, arcs again closer, and only then commits to the lunge.
func _do_circle(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	_circle_t += delta
	var d := _flat_dist(drone.global_position)
	if _sees and d <= STRIKE_RADIUS + 0.4:
		_enter_lunge()
		return
	if _circle_t >= CIRCLE_TIMEOUT and _sees:
		# Prey too quick to corner: back to shadowing, patience reset.
		_enter_prowl()
		return

	_circle_flip_t -= delta
	if _circle_flip_t <= 0.0:
		_circle_dir = -_circle_dir
		_circle_flip_t = _rng.randf_range(2.0, 4.0)

	# Sawtooth close: 1.4 s of closing, then 0.8 s of re-adjusting.
	if _circle_hold_t > 0.0:
		_circle_hold_t -= delta
	else:
		_circle_shrink_t -= delta
		_circle_radius = move_toward(_circle_radius, STRIKE_RADIUS,
				CIRCLE_CLOSE_RATE * delta)
		if _circle_shrink_t <= 0.0:
			_circle_shrink_t = CIRCLE_SHRINK_WINDOW
			_circle_hold_t = CIRCLE_HOLD_WINDOW

	_circle_angle += _circle_dir * CIRCLE_RATE * delta
	var target: Vector3 = drone.global_position + Vector3(
			cos(_circle_angle), 0.0, sin(_circle_angle)) * _circle_radius
	_seek(_nav_target(target), W_CIRCLE)


## First contact on a sound chassis: hurt it and re-arm the hunt. No catch is
## latched, so the same loop runs again and the next contact destroys it.
func _first_strike() -> void:
	_halt()
	var push: Vector3 = drone.global_position - global_position
	push.y = 0.0
	drone.apply_camera_damage(_rng, push)
	drone_struck.emit()


## The strike. The only state that may catch. Off a wall it detaches INTO the
## leap and lets gravity carry it down onto the prey. The first contact on a
## sound chassis only damages it and re-arms the hunt; the next contact kills.
func _do_lunge(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	var d := _flat_dist(drone.global_position)
	if d < CATCH_RANGE \
			and absf(global_position.y - drone.global_position.y) < CATCH_MAX_Y:
		if drone.has_method("apply_camera_damage") and not drone.camera_damaged:
			_first_strike()
			_enter_prowl()
			return
		_catch()
		return
	_seek(drone.global_position, W_LUNGE)
	_lunge_miss_t += delta
	if _lunge_miss_t <= 1.4:
		return
	# Past the drone with nothing caught: re-adjust, or drop the chase.
	var past: Vector3 = global_position - drone.global_position
	past.y = 0.0
	if past.dot(_lunge_dir) > 0.5:
		if _sees:
			_enter_circle()
		else:
			_give_up()


# --------------------------------------------------------------------------
# States: ambush
# --------------------------------------------------------------------------

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
			_remember_drone()
			_enter_prowl()
		else:
			_ambush_t = ambush_wait * 0.5


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
	if _on_wall:
		_detach()
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


## Refresh the last-seen memory: where the drone is now, the heading it was
## moving (or the bearing to it when it is creeping), and a cleared lost timer.
## Any hunt entered off sight must start from this, or a hunt that loses
## contact immediately steers at a stale or zero memory.
func _remember_drone() -> void:
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


## Flat unit heading of the drone; falls back to the bearing from the drone to
## this body when it is stationary, so an intercept still makes sense.
func _drone_heading() -> Vector3:
	if drone == null or not is_instance_valid(drone):
		return Vector3.FORWARD
	var v: Vector3 = drone.velocity
	v.y = 0.0
	if v.length() > 0.25:
		return v.normalized()
	var to: Vector3 = global_position - drone.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return Vector3.FORWARD
	return to.normalized()


func _enter_prowl(keep_patience := false) -> void:
	state = State.PROWL
	_lost_sight_t = 0.0
	_prowl_still_t = 0.0
	_ambush_spring = false
	if _on_wall:
		_detach()   # a hunt starts on the floor
	if not keep_patience:
		_kill_t = 0.0


func _enter_play() -> void:
	if drone == null or not is_instance_valid(drone):
		return
	state = State.PLAY
	_play_phase = PLAY_PHASE_RUSH
	_play_t = 0.0
	_play_recalc_t = 0.5
	_lost_sight_t = 0.0
	_play_cd = PLAY_COOLDOWN_BASE * _rng.randf_range(0.8, 1.3)
	_compute_intercept()


func _enter_circle() -> void:
	state = State.CIRCLE
	_circle_t = 0.0
	_circle_radius = clampf(_flat_dist(drone.global_position), 3.0, 7.0)
	var to_me: Vector3 = global_position - drone.global_position
	to_me.y = 0.0
	_circle_angle = 0.0
	if to_me.length() > 0.05:
		_circle_angle = atan2(to_me.z, to_me.x)
	_circle_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_circle_flip_t = _rng.randf_range(2.0, 4.0)
	_circle_shrink_t = CIRCLE_SHRINK_WINDOW
	_circle_hold_t = 0.0
	_lost_sight_t = 0.0


func _enter_lunge(from_ambush := false) -> void:
	if state == State.LUNGE:
		return
	state = State.LUNGE
	_ambush_spring = from_ambush
	_lost_sight_t = 0.0
	_lunge_miss_t = 0.0
	radar_mass_scale = 1.0
	if drone != null and is_instance_valid(drone):
		var flat: Vector3 = drone.global_position - global_position
		flat.y = 0.0
		if flat.length() > 0.05:
			_lunge_dir = flat.normalized()
		if _on_wall:
			# Off the wall it does not climb down: it leaps.
			var leap: Vector3 = (drone.global_position + Vector3(0, 0.35, 0)
					- global_position).normalized() * W_LUNGE * 1.15
			_detach(leap)
	lunge_started.emit()


func _enter_ambush() -> void:
	state = State.AMBUSH
	_ambush_t = 0.0
	radar_mass_scale = 0.30
	_kill_t = 0.0
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


func _check_stuck(delta: float) -> void:
	if state == State.SEARCH or _on_wall:
		_stuck_run = 0
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
			elif state == State.PROWL or state == State.CIRCLE \
					or state == State.PLAY:
				_enter_investigate(
						_spread_target(_last_seen_pos + _last_seen_dir * SEARCH_LEAD))
			else:
				_enter_search()
	else:
		_stuck_run = 0


func _face(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var yaw := rotation.y
	var tracking := state == State.PROWL or state == State.PLAY \
			or state == State.CIRCLE or state == State.LUNGE
	if tracking and drone != null and is_instance_valid(drone):
		yaw = _yaw_to(drone.global_position if _sees else _last_seen_pos)
	elif _on_wall and Vector2(_climb_vel.x, _climb_vel.z).length() > 0.1:
		# Purely vertical climbs have no flat heading: keep the tangent yaw the
		# attach gave it instead of snapping (atan2(0, 0) == 0) nose-in.
		yaw = atan2(-_climb_vel.x, -_climb_vel.z)
	elif velocity.length() > 0.18:
		yaw = atan2(-velocity.x, -velocity.z)
	elif state == State.SEARCH:
		yaw = _search_yaw + sin(now * 0.9) * 0.18
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 4.5, 1.0))


# --------------------------------------------------------------------------
# Climb controller: floors, walls and ceilings
# --------------------------------------------------------------------------

## Latch onto the flat surface in `dir_hint`. Returns false when there is no
## near-vertical wall within reach (the caller just stays on the floor).
func _try_attach(dir_hint: Vector3) -> bool:
	if _on_wall:
		return false
	var flat := Vector3(dir_hint.x, 0.0, dir_hint.z)
	if flat.length() < 0.05:
		return false
	flat = flat.normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.45 * BODY_SCALE, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + flat * 1.6)
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	if absf(normal.y) >= 0.35:
		return false
	# Nothing legitimate latches up on the roofline: perches top out at 2.4 m,
	# so a high hit is lintel/trim geometry, not a climbable face.
	if (hit["position"] as Vector3).y > global_position.y + 3.0:
		return false
	_on_wall = true
	_surf_up = normal.normalized()
	velocity = Vector3.ZERO
	_climb_vel = Vector3.ZERO
	_climb_blocked_t = 0.0
	global_position = hit["position"] + _surf_up * CLIMB_CLEARANCE
	# Lie along the wall, never nose-in: a forward pointing into the face would
	# bury the box's long axis in it and breaks the rig's orientation basis.
	var tangent := Vector3.UP.cross(_surf_up)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.dot(tangent) < 0.0:
		tangent = -tangent
	rotation.y = atan2(-tangent.x, -tangent.z)
	return true


## Let go. A zero impulse is a plain drop; a real impulse is a leap.
func _detach(impulse := Vector3.ZERO) -> void:
	var away := _surf_up
	_on_wall = false
	_surf_up = Vector3.UP
	_climb_goal.clear()
	_climb_vel = Vector3.ZERO
	_climb_blocked_t = 0.0
	# Resolve INTO the room, never through the surface it hugged: a body that
	# embeds in a ceiling can be depenetrated straight out the far face.
	global_position += away * 0.06
	velocity = impulse


## Walk the surface toward `_climb_goal`. No gravity, no slide: the body is
## translated directly along the surface plane, vaulting wall tops onto the
## ceiling when the surface runs out underneath it.
func _climb_tick(delta: float) -> void:
	if _climb_goal.is_empty():
		_climb_vel = Vector3.ZERO
		return
	var point: Vector3 = _climb_goal["point"]
	var v := point - global_position
	var plane_dir := v - _surf_up * v.dot(_surf_up)
	if plane_dir.length() < CLIMB_PLANE_ARRIVE:
		_climb_goal.clear()
		_climb_vel = Vector3.ZERO
		return
	var move_dir := plane_dir.normalized()
	var space := get_world_3d().direct_space_state

	# Vault: if the surface stops ahead of us, this is the wall top. Look for
	# a ceiling to flip onto; without one, drop.
	var sup_from := global_position + move_dir * 0.5 + _surf_up * 0.15
	var sq := PhysicsRayQueryParameters3D.create(sup_from, sup_from - _surf_up * 1.0)
	sq.collision_mask = 1
	var sup: Dictionary = space.intersect_ray(sq)
	if sup.is_empty():
		var c_from := global_position + move_dir * 0.5
		var cq := PhysicsRayQueryParameters3D.create(c_from, c_from + Vector3.UP * 1.4)
		cq.collision_mask = 1
		var ceiling: Dictionary = space.intersect_ray(cq)
		if not ceiling.is_empty() \
				and (ceiling["normal"] as Vector3).dot(Vector3.DOWN) > 0.6:
			_surf_up = Vector3.DOWN
			global_position = ceiling["position"] + _surf_up * CLIMB_CLEARANCE
			var v2 := point - global_position
			plane_dir = v2 - _surf_up * v2.dot(_surf_up)
			if plane_dir.length() < 0.001:
				_climb_goal.clear()
				_climb_vel = Vector3.ZERO
				return
			move_dir = plane_dir.normalized()
		else:
			_detach()
			return

	# Obstacle on the surface: slide round it, give up if it keeps blocking.
	var o_from := global_position + _surf_up * 0.1
	var oq := PhysicsRayQueryParameters3D.create(o_from, o_from + move_dir * 0.45)
	oq.collision_mask = 1
	var oh: Dictionary = space.intersect_ray(oq)
	if not oh.is_empty():
		var on: Vector3 = oh["normal"]
		if move_dir.dot(on) < -0.3:
			move_dir = move_dir.slide(on).normalized()
			_climb_blocked_t += delta
			if _climb_blocked_t > CLIMB_BLOCK_LIMIT:
				_detach()
				return
	else:
		_climb_blocked_t = 0.0

	var step := minf(CLIMB_SPEED, plane_dir.length() / maxf(delta, 0.0001)) * delta
	global_position += move_dir * step
	_climb_vel = move_dir * CLIMB_SPEED


## On a wall the body is translated by the climb controller: no gravity, no
## slide, no stuck watch. Everything else uses the shared floor locomotion.
func _move_tick(delta: float) -> void:
	if _on_wall:
		velocity = Vector3.ZERO
		return
	super._move_tick(delta)


# --------------------------------------------------------------------------
# Presentation
# --------------------------------------------------------------------------

func _animate(delta: float) -> void:
	# Pose weight: the rig rears its forelegs and opens its mandibles from it.
	var pose_target := 0.0
	if state == State.LUNGE:
		pose_target = 1.0
	elif state == State.PLAY:
		pose_target = 1.0 if _play_phase == PLAY_PHASE_HOLD else 0.55
	elif state == State.CIRCLE:
		pose_target = 0.85
	elif state == State.PROWL:
		pose_target = 0.55
	arm_reach = move_toward(arm_reach, pose_target, delta / 0.2)

	var fold := 0.0
	if state == State.AMBUSH or state == State.AMBUSH_SETUP:
		fold = 1.0
	elif state == State.CIRCLE:
		fold = 0.35

	var strike := 0.0
	if state == State.LUNGE \
			or (state == State.PLAY and _play_phase == PLAY_PHASE_HOLD):
		strike = 1.0

	var clearance := lerpf(0.26 * BODY_SCALE, 0.10 * BODY_SCALE, fold)
	if state == State.CIRCLE:
		clearance = 0.20 * BODY_SCALE

	var up := _surf_up
	var vel := velocity
	if _on_wall:
		vel = _climb_vel
	if _rig != null:
		_rig.update(delta, up, rotation.y, vel,
				get_world_3d().direct_space_state,
				clearance, fold, arm_reach, strike)

	_update_presence()
	_skitter_audio(delta)


## Eyes, radar mass and voice. Folded up is quiet and nearly invisible; the
## lunge opens the eyes wide and restores the full mass.
func _update_presence() -> void:
	var eyes := 1.0
	if state == State.AMBUSH or state == State.AMBUSH_SETUP:
		eyes = 0.01
	elif state == State.LUNGE:
		eyes = 4.0
	elif state == State.PLAY and _play_phase == PLAY_PHASE_HOLD:
		eyes = 1.6
	if _rig != null:
		_rig.set_eyes(eyes)

	if state == State.AMBUSH_SETUP:
		radar_mass_scale = 0.70
	elif state == State.AMBUSH:
		radar_mass_scale = 0.30
	else:
		radar_mass_scale = 1.0

	if _hum == null:
		return
	if state == State.AMBUSH or state == State.AMBUSH_SETUP:
		_hum.volume_db = -40.0
		_hum.pitch_scale = 0.58
		return
	var near := 0.0
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var d := global_position.distance_to(cam.global_position)
			near = clampf(1.0 - d / 18.0, 0.0, 1.0)
	_hum.volume_db = lerpf(-34.0, -2.0, near * near)
	_hum.pitch_scale = lerpf(0.82, 0.66, near)
	if state == State.PLAY and _play_phase == PLAY_PHASE_HOLD:
		# The spook: the hum rises into a rattle.
		_hum.pitch_scale = 1.15
		_hum.volume_db += 4.0


## The chitin taps: on a moving body close to the drone, a scrape every so
## often, pitched and levelled by proximity.
func _skitter_audio(delta: float) -> void:
	_skitter_t -= delta
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed <= 0.5:
		return
	if drone == null or not is_instance_valid(drone):
		return
	if _skitter_t > 0.0:
		return
	var d := global_position.distance_to(drone.global_position)
	if d > 12.0:
		return
	_skitter_t = _rng.randf_range(0.38, 0.55)
	var proximity := clampf(1.0 - d / 12.0, 0.0, 1.0)
	Sfx.play("scrape", global_position + Vector3(0, 0.2, 0) * BODY_SCALE,
			lerpf(-12.0, -6.0, proximity),
			_rng.randf_range(0.85, 1.35))
