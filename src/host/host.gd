extends CharacterBody3D
## Host silhouette M2/M3 — one body, three escalating but escapable modes.
##
## Perception lives on two channels only:
##   - NoiseBus events within a loudness-scaled hearing radius.
##   - a short sight cone with a world raycast for line of sight.
## No light raycasting, no "the monster just knows" tracking.
##
## States:
##   PATROL  — walk the authored waypoints.
##   CURIOUS — one noise: stop, remember roughly where it was, listen. It does
##             NOT walk to the sound. A player who freezes is left alone.
##   HUNT    — a second noise: walk slowly toward an IMPRECISE memory of the
##             sound, pausing to listen. It never reads the drone's position.
##   STALK   — direct sight: follow at a distance and keep line of sight.
##             Stop moving and it loses you; the search starts at the last
##             place it saw motion.
##
## The teach rule: **sight needs motion.** A drone that is not rolling is
## invisible at every range — no close-range exception. Freeze and the host
## can walk past you. Noise still gives it a place to search, so stillness
## buys safety only if you also stop being loud. Hosts are deaf to each other
## (source-tagged NoiseBus events).
##
## The authored M4 stalker is the exception in effect, not in rule: `main`
## feeds it a live lure, and `relentless` makes it close all the way once
## stalking.

signal drone_caught

enum State { PATROL, CURIOUS, HUNT, STALK }

const W_PATROL := 0.8
const W_HUNT := 1.15            # slow: the drone can outrun a hunter
const W_STALK := 1.6            # deliberate follow
const W_STALK_CLOSE := 2.0      # catch-up speed when the trail opens up

const HEARING_MULT := 20.0      # audible radius ≈ loudness * this
const LOUD_ESCALATE := 0.7      # a single bang this loud skips the listen
const ESCALATE_DELAY := 1.2     # grace before a second noise commits a hunt
const LISTEN_MIN := 2.5
const LISTEN_MAX := 4.0

const HUNT_PATIENCE := 9.0      # seconds since last noise before giving up
const HUNT_WALK_TIME := 4.0     # walk this long, then pause and listen
const HUNT_LISTEN_TIME := 1.5
const HUNT_SEARCH_TIME := 4.0   # search at the remembered point
const HUNT_ARRIVE := 0.9
const HUNT_ERROR_SCALE := 0.20  # positional error as a fraction of distance
const HUNT_ERROR_MIN := 1.0
const HUNT_ERROR_MAX := 3.0
const RELENTLESS_PATIENCE := 30.0   # authored-loss host only

const SIGHT_RANGE := 10.0
const SIGHT_FOV := 70.0         # total frontal cone, degrees
const MOVE_THRESH := 0.35       # drone speed that counts as visible motion

const STALK_KEEP := 6.5         # preferred following distance
const STALK_NEAR := 4.5         # stop closing inside this
const STALK_FAR := 9.0          # speed up beyond this
const LOSE_SIGHT_TIME := 1.5    # grace after motion stops before it searches
const CONTACT_GRACE := 0.25     # blind contact only kills this soon after losing motion
const CATCH_RANGE := 1.05
const LOSE_RANGE := 14.0        # absolute pursuit collapse

var state: int = State.PATROL
var drone = null
var waypoints: Array = []

## Authored-loss host: it still telegraphs and can be cornered, but it will not
## give up from patience or distance. Only the M4 scripted beat sets this.
var relentless := false

## The M4 shadow stalker is a distinct thing: invisible except for the giant
## shadow it throws, and a moving mass on the radar instead of noise blips.
var shadow_only := false
var giant := false
var radar_mass := false
var radar_blips := true
var low_hum := false

const Mats := preload("res://src/mats.gd")

var _wp := 0
var _rest := 0.0
var _commanded := Vector3.ZERO   # velocity we ASKED for (move_and_slide may
                                 # zero the real one against a wall)
var _heard_pos := Vector3.ZERO
var _curious_t := 0.0
var _listen_timer := 0.0
var _hunt_target := Vector3.ZERO
var _hunt_timer := 0.0           # seconds since the last heard noise
var _hunt_walk_t := 0.0
var _hunt_pause_t := 0.0
var _hunt_search_t := 0.0
var _hunt_arrived := false
var _last_seen_pos := Vector3.ZERO
var _lost_sight_t := 0.0
var _sees := false
var _caught := false
var _step_t := 0.0
var _meshes: Node3D
var _hum: AudioStreamPlayer3D = null

# Stuck watch: straight-line seek can still wedge on a corner. If the body is
# pressing but not traveling, re-route instead of standing there forever.
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _stuck_run := 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_meshes = Node3D.new()
	add_child(_meshes)
	_stuck_last = global_position
	floor_snap_length = 0.5
	# Dark mass: near-invisible until a lamp or status pool touches it.
	var torso := CSGCylinder3D.new()
	torso.radius = 0.3
	torso.height = 1.2
	torso.position = Vector3(0, 1.05, 0)
	torso.material = Mats.shadow()
	_meshes.add_child(torso)
	var head := CSGSphere3D.new()
	head.radius = 0.17
	head.position = Vector3(0, 1.8, 0.04)
	head.material = Mats.shadow()
	_meshes.add_child(head)
	for side in [-1.0, 1.0]:
		var arm := CSGBox3D.new()
		arm.size = Vector3(0.1, 0.72, 0.1)
		arm.position = Vector3(side * 0.32, 1.18, 0.06)
		arm.rotation = Vector3(0.35, 0, side * 0.1)
		arm.material = Mats.shadow()
		_meshes.add_child(arm)

	# The shadow stalker is a bigger, broader silhouette and casts only its
	# shadow. The collision body stays normal-sized so it can use the halls.
	if giant:
		_meshes.scale = Vector3(2.0, 1.45, 2.0)
		var mantle := CSGCylinder3D.new()
		mantle.radius = 0.5
		mantle.height = 0.5
		mantle.position = Vector3(0, 1.55, 0)
		mantle.material = Mats.shadow()
		_meshes.add_child(mantle)
	if shadow_only:
		for child in _meshes.get_children():
			if child is GeometryInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	# The stalker's voice: one long sub-bass note, no footsteps. Its volume
	# and pitch are driven from listener proximity in _update_visuals().
	if low_hum:
		_hum = Sfx.loop3d("stalker_hum", -34.0)
		if _hum != null:
			_hum.position = Vector3(0, 1.2, 0)
			add_child(_hum)
			_hum.play()


## Main assigns waypoints (world positions) and calls reset() once placed.
func reset() -> void:
	state = State.PATROL
	_wp = 0
	_rest = 0.0
	_curious_t = 0.0
	_listen_timer = 0.0
	_hunt_timer = 0.0
	_hunt_walk_t = 0.0
	_hunt_pause_t = 0.0
	_hunt_search_t = 0.0
	_hunt_arrived = false
	_lost_sight_t = 0.0
	_sees = false
	_caught = false
	_stuck_t = 0.0
	_stuck_run = 0
	_stuck_last = global_position


func _physics_process(delta: float) -> void:
	_step_t += delta
	_sense()
	match state:
		State.PATROL:
			_do_patrol(delta)
		State.CURIOUS:
			_do_curious(delta)
		State.HUNT:
			_do_hunt(delta)
		State.STALK:
			_do_stalk(delta)
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	move_and_slide()
	_check_stuck(delta)
	_update_visuals(delta)


## If we command motion but the body hasn't actually traveled, we are pressing
## geometry: give up on this target. Patrol reroutes; a hunt abandons the
## memory and goes back to the route.
func _check_stuck(delta: float) -> void:
	if state == State.CURIOUS or state == State.STALK:
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
			_rest = 0.0
			if state == State.PATROL:
				# Occasionally skip ahead: some corners need two reroutes to
				# get a legal angle.
				_wp = (_wp + (2 if randf() < 0.35 else 1)) % maxi(waypoints.size(), 1)
			else:
				_give_up()
	else:
		_stuck_run = 0


# --------------------------------------------------------------------------
# Perception
# --------------------------------------------------------------------------

func _sense() -> void:
	if drone == null or not is_instance_valid(drone):
		_sees = false
		# Without a drone there is nothing to stare at, but a noise memory
		# still lives: hosts can investigate the player's own footsteps.
		if state == State.STALK:
			_give_up()
		return

	_sees = _can_see_drone()
	if state != State.STALK and _sees:
		_enter_stalk()


## Sight requires motion first, then range, a frontal cone, and an
## unobstructed world ray. A parked drone is invisible at every range: the
## machine reads as scenery, not a threat, until it rolls.
func _can_see_drone() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	if not _drone_moving():
		return false
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > SIGHT_RANGE:
		return false
	if d < 0.05:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd.dot(to.normalized()) < cos(deg_to_rad(SIGHT_FOV * 0.5)):
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, 1.55, 0),
			drone.global_position + Vector3(0, 0.4, 0))
	q.collision_mask = 1          # world geometry only
	var hit := space.intersect_ray(q)
	return hit.is_empty()


## Horizontal speed only: vertical settling or a camera bob is not motion a
## host could read as a machine trying to move.
func _drone_moving() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	return Vector2(drone.velocity.x, drone.velocity.z).length() > MOVE_THRESH


func _on_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	# Hosts never hear each other. Two of them in one room otherwise lock into
	# an endless mutual-investigate loop: every footfall lands inside the
	# other's hearing radius. Their steps still post to the bus (the scanner
	# and the player's dread rely on that), but a host-sourced event is
	# invisible to every other host. Player, drone and environment noise have
	# no host source and stay audible.
	if source != null:
		if not is_instance_valid(source):
			return
		if source == self or source.is_in_group("hosts"):
			return
	if position.distance_to(global_position) < 1.2:
		return   # its own wet steps (untagged environment echo)
	var d := position.distance_to(global_position)
	if d > loudness * HEARING_MULT:
		return

	# Visual stalking already owns the target; noise cannot make it smarter.
	if state == State.STALK:
		return

	_heard_pos = position
	if state == State.PATROL:
		# A single very loud event skips the listening phase. Quiet footfalls
		# and motor hum only make it curious.
		if loudness >= LOUD_ESCALATE:
			_enter_hunt(position)
		else:
			_enter_curious(position)
	elif state == State.CURIOUS:
		if loudness >= LOUD_ESCALATE or _curious_t >= ESCALATE_DELAY:
			_enter_hunt(position)
		# Otherwise it keeps listening at the first sound. If the player
		# freezes, there is no second event and it goes back to patrol.
	elif state == State.HUNT:
		_hunt_target = _imprecise(position)
		_hunt_timer = 0.0
		_hunt_pause_t = 0.0
		_hunt_arrived = false
		_hunt_search_t = 0.0
		_hunt_walk_t = 0.0


# --------------------------------------------------------------------------
# State entry / exit
# --------------------------------------------------------------------------

func _enter_curious(pos: Vector3) -> void:
	state = State.CURIOUS
	_heard_pos = pos
	_curious_t = 0.0
	_listen_timer = _rng.randf_range(LISTEN_MIN, LISTEN_MAX)
	_halt()


func _enter_hunt(pos: Vector3, err_override: float = -1.0) -> void:
	state = State.HUNT
	_hunt_target = _imprecise(pos, err_override)
	_hunt_timer = 0.0
	_hunt_walk_t = 0.0
	_hunt_pause_t = 0.0
	_hunt_arrived = false
	_hunt_search_t = 0.0
	_lost_sight_t = 0.0


func _enter_stalk() -> void:
	state = State.STALK
	_last_seen_pos = drone.global_position
	_lost_sight_t = 0.0
	_hunt_pause_t = 0.0
	_hunt_arrived = false


## Authored-beat / test entry points. Normal play only reaches these through
## hearing and sight; the scripted M4 beat calls them directly.
func force_hunt(pos: Vector3) -> void:
	_heard_pos = pos
	_enter_hunt(pos)


func force_stalk(pos: Vector3) -> void:
	_enter_stalk()
	_last_seen_pos = pos


## Errors are re-rolled per heard event. A hunt therefore walks generally
## toward the sound, but never to the drone's actual coordinates.
func _imprecise(pos: Vector3, err_override: float = -1.0) -> Vector3:
	var flat := pos - global_position
	flat.y = 0.0
	var d := flat.length()
	if d < 0.05:
		return pos
	var err := err_override
	if err < 0.0:
		err = clampf(d * HUNT_ERROR_SCALE, HUNT_ERROR_MIN, HUNT_ERROR_MAX)
	var ang := atan2(flat.z, flat.x) + _rng.randf_range(-1.22, 1.22)
	var off := Vector3(cos(ang), 0.0, sin(ang)) * err * _rng.randf_range(0.35, 1.0)
	return pos + off


func _give_up() -> void:
	state = State.PATROL
	_wp = _nearest_wp()
	_rest = 0.0
	_curious_t = 0.0
	_listen_timer = 0.0
	_hunt_timer = 0.0
	_hunt_walk_t = 0.0
	_hunt_pause_t = 0.0
	_hunt_search_t = 0.0
	_hunt_arrived = false
	_lost_sight_t = 0.0
	_caught = false


func _catch() -> void:
	if _caught:
		return
	_caught = true
	_halt()
	drone_caught.emit()


## The fleet absorbed the loss: a surviving chassis carries the link, so this
## body has not ended the run. Let it resume its own hunt instead of freezing
## on the kill.
func release_catch() -> void:
	_give_up()


# --------------------------------------------------------------------------
# States
# --------------------------------------------------------------------------

func _do_patrol(delta: float) -> void:
	if waypoints.is_empty():
		return
	if _rest > 0.0:
		_rest -= delta
		_halt()
		return
	var target: Vector3 = waypoints[_wp]
	_seek(target, W_PATROL)
	if _flat_dist(target) < 0.4:
		_wp = (_wp + 1) % waypoints.size()
		_rest = _rng.randf_range(1.2, 2.6)


func _do_curious(delta: float) -> void:
	_curious_t += delta
	_listen_timer -= delta
	_halt()
	if _listen_timer <= 0.0:
		_give_up()


func _do_hunt(delta: float) -> void:
	_hunt_timer += delta
	var patience := RELENTLESS_PATIENCE if relentless else HUNT_PATIENCE
	if _hunt_timer >= patience:
		_give_up()
		return

	# Listening pause: head scans, body still. New noise interrupts it.
	if _hunt_pause_t > 0.0:
		_hunt_pause_t -= delta
		_halt()
		return

	# Arrived at the memory: search, then leave the player alone.
	if _hunt_arrived:
		_hunt_search_t += delta
		_halt()
		if _hunt_search_t >= HUNT_SEARCH_TIME:
			_give_up()
		return

	if _flat_dist(_hunt_target) <= HUNT_ARRIVE:
		_hunt_arrived = true
		_hunt_search_t = 0.0
		_halt()
		return

	_seek(_hunt_target, W_HUNT)
	_hunt_walk_t += delta
	if _hunt_walk_t >= HUNT_WALK_TIME:
		_hunt_walk_t = 0.0
		_hunt_pause_t = HUNT_LISTEN_TIME
		_halt()


func _do_stalk(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()

	# Contact kills if it still has eyes on you, if it only just lost the
	# sight of your motion, or if this is the authored relentless host. A
	# drone parked long enough is furniture: the host can walk over it.
	if d < CATCH_RANGE and (_sees or _lost_sight_t < CONTACT_GRACE or relentless):
		_catch()
		return

	if _sees:
		_lost_sight_t = 0.0
		_last_seen_pos = drone.global_position

		# Free hosts hold a following distance. The authored-loss host closes
		# all the way; it is fed a live lure by main, not given special sight.
		var hold: float = (STALK_NEAR + 0.3) if relentless else (STALK_KEEP + 0.3)
		if d > hold:
			var spd := W_STALK_CLOSE if d > STALK_FAR else W_STALK
			_seek(drone.global_position, spd)
		else:
			_halt()
	else:
		# Sight broken. It only has the last place it actually saw motion.
		_lost_sight_t += delta
		if _lost_sight_t < LOSE_SIGHT_TIME:
			_seek(_last_seen_pos, W_HUNT)
		else:
			# Search the corner it vanished around, with a little uncertainty.
			_enter_hunt(_last_seen_pos, 0.8)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

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


func _update_visuals(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var yaw := rotation.y
	var wobble := sin(Time.get_ticks_msec() / 1000.0 * 1.3) * 0.45
	if state == State.STALK and drone != null and is_instance_valid(drone):
		yaw = _yaw_to(drone.global_position if _sees else _last_seen_pos)
	elif state == State.CURIOUS:
		yaw = _yaw_to(_heard_pos) + wobble
	elif state == State.HUNT and hspeed < 0.15:
		var look: Vector3 = _heard_pos if (_hunt_pause_t > 0.0 or _hunt_arrived) \
				else _hunt_target
		yaw = _yaw_to(look) + wobble
	elif hspeed > 0.15:
		yaw = atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))
	# Shamble sway, faster when moving.
	_meshes.rotation.z = sin(Time.get_ticks_msec() / 1000.0 * hspeed * 2.4) * 0.06
	# Wet steps, posted to the bus so the scanner remembers where it lives.
	# The stalker has no steps: its hum carries the whole performance.
	if not low_hum and hspeed > 0.15 \
			and _step_t > _rng.randf_range(0.65, 1.1) / maxf(hspeed, 0.4):
		_step_t = 0.0
		Sfx.play("hstep", global_position, -6.0, randf_range(0.85, 1.1))
		# Source-tagged: the bus and the scanner hear this, other hosts do not.
		NoiseBus.emit_noise(global_position, 0.33, self)
	if _hum != null:
		var cam := get_viewport().get_camera_3d()
		var near := 0.0
		if cam != null:
			var d := global_position.distance_to(cam.global_position)
			near = clampf(1.0 - d / 18.0, 0.0, 1.0)
		_hum.volume_db = lerpf(-34.0, -2.0, near * near)
		_hum.pitch_scale = lerpf(0.82, 0.66, near)
