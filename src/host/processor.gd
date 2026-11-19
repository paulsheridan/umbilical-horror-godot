extends CharacterBody3D
## The Processor — the last body. A pinned giant mouth on two legs at the end
## of the new east hall. It never walks. The Collector brings it the crew's
## remains; it picks parts off the pile with one gaunt hand, puts them in its
## mouth, and consumes them.
##
## It has no hearing model and no patrol: it watches one thing, motion in its
## chamber. A chassis that stops is furniture. A chassis that drives is food,
## and the two cube hands reach for it. The reach is slow and telegraphed, so
## the escape is to drive clear of the chamber before the hand arrives.

signal drone_caught

enum State { IDLE, TELEGRAPH, REACH, RETRACT, DEVOUR }

const SIGHT_RANGE := 15.0
const SIGHT_FOV := 145.0
const EYE_HEIGHT := 2.45
const MOVE_THRESH := 0.30
const TELEGRAPH_TIME := 1.05
const REACH_TIME := 0.95
const RETRACT_TIME := 0.70
const CATCH_COOLDOWN := 2.4
const HAND_SPEED := 5.2
const MAX_REACH := 3.5
const GRAB_RADIUS := 0.95

const FEED_INTERVAL := 2.4
const FEED_TO_PILE := 1.1
const FEED_TO_MOUTH := 1.2
const CHEW_TIME := 0.9

## Local rig coordinates. The Processor is pinned and only rotates its arms,
# the mouth and its jaw; the body itself never moves.
const SHOULDER_L := Vector3(-1.00, 2.45, 0.0)
const SHOULDER_R := Vector3(1.00, 2.45, 0.0)
const REST_L := Vector3(-1.05, 1.05, -0.55)
const REST_R := Vector3(1.05, 1.05, -0.55)
const MOUTH := Vector3(0.0, 2.28, -0.80)

var drone = null
## The pile the Collector feeds. Its visible children are the body parts this
## body eats, one at a time.
var pile: Node3D = null
## Kept off the radar: the room is the warning, not a moving mass.
var radar_blips := false
var state: int = State.IDLE
var consumed := 0
var catches := 0
var pinned := true
## After the Collector gives itself to the maw, the Processor goes inert: no
## reach, no feeding, no new catches. The wing becomes a dead room with a
## lantern and a sack on the deck.
var dormant := false
## Debug vision: no sight, no reach, no catch. Main sets this on its toggle.
var ghosted := false

var _state_t := 0.0
var _catch_cd := 0.0
var _caught := false
var _devour_bot: Node3D = null

var _feed_cd := 0.0
var _feed_state := 0
var _feed_t := 0.0
var _feed_part: Node3D = null
var _chew := 0.0
## Child count of the pile at the last scan that found nothing to feed. A scan
## that fails cannot succeed again until the count changes (a deposit appends,
## a consumed part queue_free()s), so the whole pile is not re-read every frame.
var _pile_scan_count := -1

var _rig: Node3D
var _jaw: Node3D
var _mouth_glow: OmniLight3D
var _arm_pivots: Array = []
var _arm_meshes: Array = []
var _hands: Array = []
var _hand_local: Array = []
var _hand_target: Array = []
var _reach_target := REST_R


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")
	floor_snap_length = 0.5
	# The body is authored in scenes/actors/processor.tscn.
	_resolve_body()
	reset()


func _resolve_body() -> void:
	_rig = $Rig
	_jaw = _rig.get_node("Jaw")
	_mouth_glow = _rig.get_node("MouthGlow")
	_arm_pivots = [_rig.get_node("ArmL"), _rig.get_node("ArmR")]
	_arm_meshes = [(_arm_pivots[0] as Node).get_node("Arm"),
			(_arm_pivots[1] as Node).get_node("Arm")]
	_hands = [(_arm_pivots[0] as Node).get_node("Hand"),
			(_arm_pivots[1] as Node).get_node("Hand")]


func reset() -> void:
	state = State.IDLE
	_state_t = 0.0
	_catch_cd = 0.0
	_caught = false
	_devour_bot = null
	_feed_cd = 1.2
	_feed_state = 0
	_feed_t = 0.0
	_feed_part = null
	_chew = 0.0
	_pile_scan_count = -1
	_reach_target = REST_R
	_hand_local = [REST_L, REST_R]
	_hand_target = [REST_L, REST_R]
	if _jaw != null:
		_jaw.rotation.x = -0.06


func set_dormant(on: bool) -> void:
	dormant = on
	if not dormant:
		return
	_devour_bot = null
	_feed_part = null
	_feed_state = 0
	_feed_t = 0.0
	_chew = 0.0
	state = State.IDLE
	_state_t = 0.0
	_hand_target = [REST_L, REST_R]
	_reach_target = REST_R
	_caught = false


func _physics_process(delta: float) -> void:
	if GameState.paused:
		return
	if dormant:
		_aim_hands(delta)
		_animate(delta)
		return
	if ghosted:
		# Debug vision: drop any queued meal and go still. The body animates,
		# but it never sees or reaches for the fleet.
		_devour_bot = null
		_feed_part = null
		_caught = false
		_aim_hands(delta)
		_animate(delta)
		return
	_catch_cd = maxf(_catch_cd - delta, 0.0)
	_state_t += delta

	if _devour_bot != null and not is_instance_valid(_devour_bot):
		_devour_bot = null
		if state == State.DEVOUR:
			_begin_retract()

	match state:
		State.IDLE:
			_feed_tick(delta)
			_hand_target[1] = REST_R
			if _catch_cd <= 0.0 and _can_see_drone():
				_enter_telegraph()
		State.TELEGRAPH:
			_hand_target[1] = _reach_target
			if _state_t >= TELEGRAPH_TIME:
				state = State.REACH
				_state_t = 0.0
				_reach_target = _drone_local_target()
		State.REACH:
			if drone == null or not is_instance_valid(drone):
				_begin_retract()
			else:
				_reach_target = _drone_local_target()
				_hand_target[1] = _reach_target
				var gp: Vector3 = drone.global_position + Vector3(0, 0.35, 0)
				if _hands[1].global_position.distance_to(gp) < GRAB_RADIUS \
						and not drone.get("carried"):
					_catch()
				elif _state_t >= REACH_TIME:
					_begin_retract()
		State.RETRACT:
			_hand_target[1] = REST_R
			if _state_t >= RETRACT_TIME:
				state = State.IDLE
				_state_t = 0.0
				_catch_cd = CATCH_COOLDOWN
		State.DEVOUR:
			_devour_tick(delta)

	_aim_hands(delta)
	_animate(delta)


# --------------------------------------------------------------------------
# Perception / reach
# --------------------------------------------------------------------------

## Motion in the chamber, then range, then a wide frontal cone and a clear
## ray. A still chassis is invisible at every range: the mouth does not chase
## furniture, and the player can watch it feed without being seen.
func _can_see_drone() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	if drone.get("carried") == true:
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
			to_global(Vector3(0, EYE_HEIGHT, -0.6)),
			drone.global_position + Vector3(0, 0.4, 0))
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _drone_moving() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	return Vector2(drone.velocity.x, drone.velocity.z).length() > MOVE_THRESH


func _drone_local_target() -> Vector3:
	if drone == null or not is_instance_valid(drone):
		return REST_R
	return _rig.to_local(drone.global_position + Vector3(0, 0.40, 0))


func _enter_telegraph() -> void:
	state = State.TELEGRAPH
	_state_t = 0.0
	_reach_target = _drone_local_target()
	_hand_target[1] = _reach_target
	# The whole room hears the mouth working before the hand moves. The
	# Processor does not post to NoiseBus: it is a fixture, and the Stalker
	# has no business being lured into its chamber.
	Sfx.play("thud", global_position, -2.0, 0.72)


func _catch() -> void:
	if _caught:
		return
	_caught = true
	catches += 1
	_devour_bot = drone
	state = State.DEVOUR
	_state_t = 0.0
	_chew = 1.0
	drone_caught.emit()


func _devour_tick(delta: float) -> void:
	if _devour_bot == null or not is_instance_valid(_devour_bot):
		_devour_bot = null
		_begin_retract()
		return
	var mouth: Vector3 = _rig.to_global(MOUTH + Vector3(0, 0, -0.10))
	_devour_bot.global_position = _devour_bot.global_position.lerp(
			mouth, minf(delta * 3.2, 1.0))
	_devour_bot.velocity = Vector3.ZERO
	_hand_target[1] = MOUTH + Vector3(0.55, -0.1, 0.0)
	_chew = maxf(0.35, 1.0 - _state_t * 0.45)


func _begin_retract() -> void:
	state = State.RETRACT
	_state_t = 0.0
	_reach_target = REST_R
	_hand_target[1] = REST_R
	_chew = 0.0
	_caught = false


## The fleet absorbed the loss: a surviving chassis carries the link, so the
## Processor lets the eaten body go and resumes watching its pile.
func release_catch() -> void:
	_devour_bot = null
	_begin_retract()


# --------------------------------------------------------------------------
# Hands / feeding
# --------------------------------------------------------------------------

func _aim_hands(delta: float) -> void:
	for i in 2:
		var shoulder: Vector3 = SHOULDER_L if i == 0 else SHOULDER_R
		var target: Vector3 = _hand_target[i]
		var rel: Vector3 = target - shoulder
		if rel.length() > MAX_REACH:
			target = shoulder + rel.normalized() * MAX_REACH
		_hand_local[i] = (_hand_local[i] as Vector3).move_toward(
				target, HAND_SPEED * delta)
		# Never let a target outside the chamber stretch the arm past its
		# authored reach; the hand stops at the edge of what this body owns.
		var held: Vector3 = (_hand_local[i] as Vector3) - shoulder
		if held.length() > MAX_REACH:
			_hand_local[i] = shoulder + held.normalized() * MAX_REACH
		_apply_hand(i, _hand_local[i])


func _apply_hand(i: int, local_pos: Vector3) -> void:
	var shoulder: Vector3 = SHOULDER_L if i == 0 else SHOULDER_R
	var rel: Vector3 = local_pos - shoulder
	var length := clampf(rel.length(), 0.45, MAX_REACH)
	var dir := rel.normalized() if rel.length() > 0.001 else Vector3(0, 0, -1)
	var pivot: Node3D = _arm_pivots[i]
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.BACK
	pivot.position = shoulder
	pivot.look_at(_rig.to_global(shoulder + dir * length), up)
	var mesh: CSGBox3D = _arm_meshes[i]
	mesh.scale = Vector3(1, 1, length)
	mesh.position = Vector3(0, 0, -length * 0.5)
	(_hands[i] as CSGBox3D).position = Vector3(0, 0, -length)


func _feed_tick(delta: float) -> void:
	_feed_cd = maxf(_feed_cd - delta, 0.0)
	if _feed_state == 0:
		_hand_target[0] = REST_L
		if _feed_cd <= 0.0 and pile != null and is_instance_valid(pile):
			var part := _next_pile_part()
			if part != null:
				_feed_part = part
				_feed_state = 1
				_feed_t = 0.0
				_hand_target[0] = _rig.to_local(part.global_position)
		return
	if _feed_part == null or not is_instance_valid(_feed_part):
		_feed_part = null
		_feed_state = 0
		_hand_target[0] = REST_L
		return
	match _feed_state:
		1:
			_feed_t += delta
			if _hands[0].global_position.distance_to(_feed_part.global_position) < 0.38 \
					or _feed_t > FEED_TO_PILE:
				_feed_state = 2
				_feed_t = 0.0
				_hand_target[0] = MOUTH
		2:
			_feed_t += delta
			_feed_part.global_position = _hands[0].global_position
			if _hands[0].global_position.distance_to(_rig.to_global(MOUTH)) < 0.42 \
					or _feed_t > FEED_TO_MOUTH:
				_feed_state = 3
				_feed_t = 0.0
				_feed_part.visible = false
				_chew = 1.0
				Sfx.play("thud", _rig.to_global(MOUTH), -8.0, 0.58)
		3:
			_feed_t += delta
			_chew = maxf(0.0, 1.0 - _feed_t / CHEW_TIME)
			if _feed_t >= CHEW_TIME:
				if is_instance_valid(_feed_part):
					_feed_part.queue_free()
				_feed_part = null
				consumed += 1
				_feed_state = 4
				_feed_cd = FEED_INTERVAL
				_hand_target[0] = REST_L
		4:
			if _hands[0].global_position.distance_to(_rig.to_global(REST_L)) < 0.30:
				_feed_state = 0


## The top feedable body part on the pile. The old heap is tagged as dressing
## so the chamber never empties; the Collector's fresh deposits are the food.
## A failed scan is remembered by child count: nothing can turn a part feedable
## again without the pile gaining or losing a child, so repeat misses are free.
func _next_pile_part() -> Node3D:
	if pile == null or not is_instance_valid(pile):
		return null
	var count := pile.get_child_count()
	if count == _pile_scan_count:
		return null
	var kids := pile.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var n = kids[i]
		if n is Node3D and n.visible and not n.get_meta("dressing", false):
			# A hit resets the memo so the next pickup scans normally.
			_pile_scan_count = -1
			return n
	_pile_scan_count = count
	return null


# --------------------------------------------------------------------------
# Body + animation
# --------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if dormant:
		if _jaw != null:
			_jaw.rotation.x = lerpf(_jaw.rotation.x, -0.02, minf(delta * 2.0, 1.0))
		if _mouth_glow != null:
			_mouth_glow.light_energy = lerpf(_mouth_glow.light_energy, 0.02,
					minf(delta * 2.0, 1.0))
		if _rig != null:
			_rig.rotation.z = lerpf(_rig.rotation.z, 0.0, minf(delta * 2.0, 1.0))
		return
	var open := 0.06
	match state:
		State.TELEGRAPH:
			open = 0.12 + 0.75 * clampf(_state_t / TELEGRAPH_TIME, 0.0, 1.0)
		State.REACH, State.DEVOUR:
			open = 0.92
		_:
			open = 0.06 + _chew * 0.28
	var chatter := _chew * 0.16 * sin(Time.get_ticks_msec() / 1000.0 * 19.0)
	var jaw_target := -(open + chatter)
	if _jaw != null:
		_jaw.rotation.x = lerpf(_jaw.rotation.x, jaw_target,
				minf(delta * 8.0, 1.0))
	if _rig != null:
		_rig.rotation.z = sin(Time.get_ticks_msec() / 1000.0 * 0.55) * 0.012
	if _mouth_glow != null:
		var pulse := 0.62 + 0.12 * sin(Time.get_ticks_msec() / 1000.0 * 2.3)
		if state == State.TELEGRAPH or state == State.REACH:
			pulse += 0.45
		_mouth_glow.light_energy = pulse
