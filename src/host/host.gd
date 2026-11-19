extends "res://src/host/host_base.gd"
## Host silhouette M2/M3 — one body, three escalating but escapable modes.
##
## Perception lives on two channels only:
##   - NoiseBus events within a loudness-scaled hearing radius.
##   - a short sight cone with a world raycast for line of sight, plus the
##     drone's flashlight beam: an unoccluded lit chassis is an instant beacon.
## No "the monster just knows" tracking; every sight rule still runs through
## the world raycast.
##
## States:
##   PATROL  — walk the authored waypoints.
##   CURIOUS — one noise: stop, remember roughly where it was, listen. It does
##             NOT walk to the sound. A player who freezes is left alone.
##   HUNT    — a second noise: walk slowly toward an IMPRECISE memory of the
##             sound, pausing to listen. It never reads the drone's position.
##   STALK   — direct sight: run the drone down and kill on contact. Stop
##             moving and it loses you; the search starts at the last place
##             it saw motion.
##
## The teach rule: **sight needs motion** — except for the flashlight. A drone
## that is not rolling is invisible at every range with the lamp off; freeze
## and the host can walk past you. Switch the beam on with a clear line of
## sight and the lamp itself is the tell: every host that can see the light
## turns and pursues, whatever its facing or the old range. Cover still works;
## a wall breaks the beam. Noise still gives it a place to search, so darkness
## and silence are what buy safety. Hosts are deaf to each other
## (source-tagged NoiseBus events).
##
## The engine-room Stalker uses its own script/body; this host flag is retained
## for a relentless variant and is not set by the shipped level.
##
## The Watcher (src/host/watcher.gd) subclasses this body to plant at a
## stand-off and watch instead of attacking — the shipped Cold Hold population
## is watchers. The Host itself closes all the way and kills on contact.

enum State { PATROL, CURIOUS, HUNT, STALK }

const W_PATROL := 0.8
const W_HUNT := 1.15            # slow: the drone can outrun a hunter
const W_STALK := 1.6            # deliberate follow
const W_STALK_CLOSE := 2.0      # catch-up speed when the trail opens up

## The Kenney locomotion clips are the same rig family the Collector uses.
## Walk covers patrol and the slow hunt; run is reserved for pursuit, so a
## host pacing its route never reads as a sprinter.
const ANIM_BLEND := 0.18
const WALK_ANIM_SPEED := 0.9    # a heavier shamble than the raw clip

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
## A lit chassis is a beacon: longer eyes, a wider cone, and the stillness
## rule is suspended entirely. This is the flashlight's cost.
const LIGHT_SIGHT_MULT := 1.6
const LIGHT_FOV_MULT := 1.15

const STALK_FAR := 9.0          # speed up beyond this
const LOSE_SIGHT_TIME := 1.5    # grace after motion stops before it searches
const CONTACT_GRACE := 0.25     # blind contact only kills this soon after losing motion
const CATCH_RANGE := 1.05
const LOSE_RANGE := 14.0        # absolute pursuit collapse

## Per-body tuning. Base values reproduce the old patrol host exactly; the
## Cold Hold's aggressive bodies override these through configure_aggressive().
## Keeping them as vars (not constants) means tests and editor placement can
## tweak one body without changing every host in the ship.
var sight_range := SIGHT_RANGE
var sight_fov := SIGHT_FOV
var move_thresh := MOVE_THRESH
## Still drones are invisible by default. Zone 2 bodies can see a parked
## chassis inside this short radius, which is what makes stopping a gamble
## there rather than an invisibility cloak.
var still_sight_range := 0.0
var loud_escalate := LOUD_ESCALATE
var w_patrol := W_PATROL
var w_hunt := W_HUNT
var w_stalk := W_STALK
var w_stalk_close := W_STALK_CLOSE
var hunt_patience := HUNT_PATIENCE
var hunt_error_scale := HUNT_ERROR_SCALE
var hunt_error_min := HUNT_ERROR_MIN
var hunt_error_max := HUNT_ERROR_MAX
## Audible breathing, driven by proximity. Zone 2 bodies are read by sound
## and lamp-light before they are ever seen.
var breathing := false

## Relentless host: it still telegraphs and can be cornered, but it will not
## give up from patience or distance. No live host sets it; the engine Stalker
## is a separate script.
var relentless := false

## A radar mass is a broad moving body rather than a noise blip.
var radar_mass := false
var radar_blips := true
var low_hum := false


var _heard_pos := Vector3.ZERO
var _curious_t := 0.0
var _listen_timer := 0.0
var _hunt_target := Vector3.ZERO
var _hunt_timer := 0.0           # seconds since the last heard noise
var _hunt_walk_t := 0.0
var _hunt_pause_t := 0.0
var _hunt_search_t := 0.0
var _hunt_arrived := false
var _step_t := 0.0
var _meshes: Node3D
var _anim: AnimationPlayer
var _anim_name := ""
var _skeleton: Skeleton3D
var _breath: AudioStreamPlayer3D = null

## Arms-held-out reach, 0..1. The locomotion clip owns every bone, so the pose
## is layered on after animation (see ReachModifier); at 0 the authored clip is
## untouched. Read by the focused reach probe.
var reach_weight := 0.0
var _reach: ReachModifier = null


func _ready() -> void:
	_body_ready()
	# The body is authored in scenes/actors/host.tscn.
	_meshes = $Meshes
	_anim = $Meshes/AnimationPlayer
	_skeleton = $Meshes/Model/Root/Skeleton3D
	_build_reach()
	_play_anim("idle", true)
	_stuck_last = global_position
	# The stalker's voice: one long sub-bass note, no footsteps. Its volume
	# and pitch are driven from listener proximity in _update_visuals().
	if low_hum:
		_hum = Sfx.loop3d("stalker_hum", -34.0)
		if _hum != null:
			_hum.position = Vector3(0, 1.2, 0)
			add_child(_hum)
			_hum.play()
	if breathing:
		_breath = Sfx.loop3d("breath", -40.0)
		if _breath != null:
			_breath.position = Vector3(0, 1.5, 0)
			add_child(_breath)
			_breath.play()


## Zone 2 profile: wider eyes, a real memory, and a body that commits. It is
## still escapable: break the ray or stop rolling outside the short still
## radius and it searches the last place it saw motion instead of tracking an
## invisible coordinate.
func configure_aggressive() -> void:
	sight_range = 21.0
	sight_fov = 105.0
	move_thresh = 0.12
	still_sight_range = 5.0
	hearing_mult = 28.0
	loud_escalate = 0.62
	w_patrol = 1.4
	w_hunt = 2.0
	w_stalk = 2.6
	w_stalk_close = 2.9
	hunt_patience = 20.0
	hunt_error_scale = 0.10
	hunt_error_min = 0.5
	hunt_error_max = 1.4
	breathing = true

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
	reach_weight = 0.0
	if _reach != null:
		_reach.influence = 0.0


func _physics_process(delta: float) -> void:
	# ESC pause freezes the drone; a host that kept walking would stalk and
	# catch through the veil, so the whole body sleeps with the pilot.
	if GameState.paused:
		return
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
	_move_tick(delta)
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
	_unlatch_spurned_catch()
	if ghosted:
		_sees = false
		if state == State.STALK:
			_give_up()
		return
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
##
## The flashlight is the one exception. Its beam is a beacon: if the lit
## chassis has a clear world-geometry line of sight, this body sees it no
## matter which way it is facing, how far away it is, or whether the drone is
## moving. Only an actual occluder (a wall, a bulkhead) defeats it.
func _can_see_drone() -> bool:
	if ghosted:
		return false
	if drone == null or not is_instance_valid(drone):
		return false
	if _drone_lit():
		# The beam is the tell. The tail already answers exactly this case
		# (lit range/cone pass, then the same world ray), so go straight there.
		return _clear_los()
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var lit := _drone_lit()
	# Motion is the tell. The base host cannot see a parked drone at all; a
	# Zone 2 body can, but only inside arm's reach of its lamp. A lit chassis
	# is the exception: the beam itself is the tell, at every range.
	if not lit and not _drone_moving():
		if still_sight_range <= 0.0 or d > still_sight_range:
			return false
	var max_range: float = sight_range * (LIGHT_SIGHT_MULT if lit else 1.0)
	if d > max_range:
		return false
	if d < 0.05:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cone: float = sight_fov * (LIGHT_FOV_MULT if lit else 1.0)
	if fwd.dot(to.normalized()) < cos(deg_to_rad(cone * 0.5)):
		return false
	return _clear_los()


## World geometry only (collision layer 1): hosts never occlude each other's
## sight, and the drone's own body is not an occluder.
func _clear_los() -> bool:
	if drone == null or not is_instance_valid(drone):
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
	return Vector2(drone.velocity.x, drone.velocity.z).length() > move_thresh


func _on_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	if not _noise_audible(position, loudness, source):
		return

	# Visual stalking already owns the target; noise cannot make it smarter.
	if state == State.STALK:
		return

	_heard_pos = position
	if state == State.PATROL:
		# A single very loud event skips the listening phase. Quiet footfalls
		# and motor hum only make it curious.
		if loudness >= loud_escalate:
			_enter_hunt(position)
		else:
			_enter_curious(position)
	elif state == State.CURIOUS:
		if loudness >= loud_escalate or _curious_t >= ESCALATE_DELAY:
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


## Test entry points. Normal play only reaches these through hearing and sight;
## the AI-rule suites call them directly.
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
		err = clampf(d * hunt_error_scale, hunt_error_min, hunt_error_max)
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
	_seek(target, w_patrol)
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
	var patience := RELENTLESS_PATIENCE if relentless else hunt_patience
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

	_seek(_hunt_target, w_hunt)
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
		# Attack: run the drone down and kill on contact. (The old body held
		# a following distance and only killed what walked into it — that
		# behaviour now belongs to the Watcher, src/host/watcher.gd.)
		var spd := w_stalk_close if d > STALK_FAR else w_stalk
		_seek(drone.global_position, spd)
	else:
		# Sight broken. It only has the last place it actually saw motion.
		_lost_sight_t += delta
		if _lost_sight_t < LOSE_SIGHT_TIME:
			_seek(_last_seen_pos, w_hunt)
		else:
			# Search the corner it vanished around, with a little uncertainty.
			_enter_hunt(_last_seen_pos, 0.8)


func _update_visuals(delta: float) -> void:
	var ticks := Time.get_ticks_msec()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var yaw := rotation.y
	if state == State.STALK and drone != null and is_instance_valid(drone):
		yaw = _yaw_to(drone.global_position if _sees else _last_seen_pos)
	elif state == State.CURIOUS:
		var wobble := sin(ticks / 1000.0 * 1.3) * 0.45
		yaw = _yaw_to(_heard_pos) + wobble
	elif state == State.HUNT and hspeed < 0.15:
		var look: Vector3 = _heard_pos if (_hunt_pause_t > 0.0 or _hunt_arrived) \
				else _hunt_target
		var wobble := sin(ticks / 1000.0 * 1.3) * 0.45
		yaw = _yaw_to(look) + wobble
	elif hspeed > 0.15:
		yaw = atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))
	# Kenney locomotion: idle when planted, walk on the patrol/hunt, and run
	# only when this body is actively pursuing the drone. Playback speed
	# follows ground speed so the shuffle does not skate at Zone 2 pace.
	var want := "idle"
	if hspeed > 0.15:
		want = "run" if state == State.STALK else "walk"
	_play_anim(want)
	if _anim != null:
		if _anim_name == "walk":
			_anim.speed_scale = clampf(hspeed / 0.9, 0.7, 1.5)
		elif _anim_name == "run":
			_anim.speed_scale = clampf(hspeed / 2.2, 0.8, 1.35)
		else:
			_anim.speed_scale = 1.0
	# Shamble sway, faster when moving.
	_meshes.rotation.z = sin(ticks / 1000.0 * hspeed * 2.4) * 0.06
	_update_reach(delta, hspeed)
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
	if _breath != null:
		# Wet, laboured breathing: audible before the body is legible, and
		# faster while it is hunting. This is the lamp's audio twin.
		var cam := get_viewport().get_camera_3d()
		var near := 0.0
		if cam != null:
			var d := global_position.distance_to(cam.global_position)
			near = clampf(1.0 - d / 22.0, 0.0, 1.0)
		var volume := lerpf(-42.0, -4.0, near * near)
		_breath.volume_db = volume
		_breath.pitch_scale = 1.22 if state == State.STALK else 0.92


## Switch locomotion clips without restarting the same one every frame. The
## Kenney library is shared by rig family, so idle/walk/run resolve directly.
func _play_anim(name: String, force := false) -> void:
	if _anim == null:
		return
	if not force and _anim_name == name:
		return
	if not _anim.has_animation(name):
		return
	_anim_name = name
	_anim.play(name, ANIM_BLEND)


## A modifier is the only post-animation hook: the imported clip rewrites the
## whole skeleton every frame, so a bone edit from _physics_process never
## survives. Added at runtime because it has to live inside the instanced rig.
func _build_reach() -> void:
	if _skeleton == null:
		return
	_reach = ReachModifier.new()
	_reach.name = "ReachAim"
	_reach.body = self
	_skeleton.add_child(_reach)


## The hands come out only in the chase state, while the body is actually
## running at the drone and can still see it. Everything else — patrol, a
## noise hunt, a watcher planted at its stand-off, a lost trail, a ghosted
## debug body — decays the weight to zero and hands the arms back to the
## authored clip.
func _update_reach(delta: float, hspeed: float) -> void:
	var want := 0.0
	if state == State.STALK and _sees and hspeed > 0.15 \
			and not ghosted and drone != null and is_instance_valid(drone):
		want = 1.0
	reach_weight = move_toward(reach_weight, want, delta / 0.2)
	if _reach == null:
		return
	_reach.influence = reach_weight
	if reach_weight > 0.0 and drone != null and is_instance_valid(drone):
		_reach.target = drone.global_position + Vector3.UP * 0.45


## Aims the two arm segments at the drone after the locomotion clip has run.
## Each segment takes the shortest arc from where the clip put it toward the
## target, so the shoulders never fold backwards and the elbow keeps its hinge
## direction. influence is the crossfade: at 0 the skeleton blends every bone
## straight back to the authored clip, which is how the run takes over again.
class ReachModifier extends SkeletonModifier3D:
	var target := Vector3.ZERO
	var body: Node3D
	## Shoulder-width split so both hands do not converge on one point.
	var split := 0.16

	var _arm_l := -1
	var _arm_r := -1
	var _fore_l := -1
	var _fore_r := -1
	var _hand_l := -1
	var _hand_r := -1
	var _side_l := 1.0
	var _side_r := -1.0

	func _process_modification_with_delta(_delta: float) -> void:
		if influence <= 0.001 or body == null:
			return
		var skel := get_skeleton()
		if skel == null:
			return
		if _arm_l < 0:
			_resolve(skel)
		if _arm_l < 0:
			return
		var inv := skel.global_transform.affine_inverse()
		var goal := inv * target
		# The rig's own lateral axis, converted out of world metres. The rest
		# pose says which shoulder sits on which side, so mirrored rigs work.
		var lateral: Vector3 = inv.basis * (body.global_transform.basis.x * split)
		_aim(skel, _arm_l, _fore_l, goal + lateral * _side_l)
		_aim(skel, _fore_l, _hand_l, goal + lateral * _side_l)
		_aim(skel, _arm_r, _fore_r, goal + lateral * _side_r)
		_aim(skel, _fore_r, _hand_r, goal + lateral * _side_r)

	func _resolve(skel: Skeleton3D) -> void:
		_arm_l = skel.find_bone("LeftArm")
		_arm_r = skel.find_bone("RightArm")
		_fore_l = skel.find_bone("LeftForeArm")
		_fore_r = skel.find_bone("RightForeArm")
		_hand_l = skel.find_bone("LeftHand")
		_hand_r = skel.find_bone("RightHand")
		var chest := skel.find_bone("Chest")
		if _arm_l < 0 or _arm_r < 0 or _fore_l < 0 or _fore_r < 0 \
				or _hand_l < 0 or _hand_r < 0 or chest < 0:
			_arm_l = -1
			return
		var mid := skel.get_bone_global_rest(chest).origin
		_side_l = signf(skel.get_bone_global_rest(_arm_l).origin.x - mid.x)
		_side_r = signf(skel.get_bone_global_rest(_arm_r).origin.x - mid.x)
		if _side_l == 0.0:
			_side_l = 1.0
		if _side_r == 0.0:
			_side_r = -1.0

	func _aim(skel: Skeleton3D, bone: int, child: int, goal: Vector3) -> void:
		if bone < 0 or child < 0:
			return
		var pose := skel.get_bone_global_pose(bone)
		var cur: Vector3 = skel.get_bone_global_pose(child).origin - pose.origin
		var want: Vector3 = goal - pose.origin
		if cur.length_squared() < 0.0000001 or want.length_squared() < 0.0000001:
			return
		var delta := Quaternion(cur.normalized(), want.normalized())
		var wished := Transform3D(Basis(delta) * pose.basis, pose.origin)
		var parent := skel.get_bone_parent(bone)
		var local := wished
		if parent >= 0:
			local = skel.get_bone_global_pose(parent).affine_inverse() * wished
		skel.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
