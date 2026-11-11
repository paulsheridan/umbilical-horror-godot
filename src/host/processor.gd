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

const Mats := preload("res://src/mats.gd")

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

var _state_t := 0.0
var _catch_cd := 0.0
var _caught := false
var _devour_bot: Node3D = null

var _feed_cd := 0.0
var _feed_state := 0
var _feed_t := 0.0
var _feed_part: Node3D = null
var _chew := 0.0

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
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.75
	capsule.height = 2.6
	col.shape = capsule
	col.position = Vector3(0, 1.3, 0)
	add_child(col)
	_build_body()
	reset()


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
	_reach_target = REST_R
	_hand_local = [REST_L, REST_R]
	_hand_target = [REST_L, REST_R]
	if _jaw != null:
		_jaw.rotation.x = -0.06


func _physics_process(delta: float) -> void:
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
func _next_pile_part() -> Node3D:
	if pile == null or not is_instance_valid(pile):
		return null
	var kids := pile.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var n = kids[i]
		if n is Node3D and n.visible and not n.get_meta("dressing", false):
			return n
	return null


# --------------------------------------------------------------------------
# Body + animation
# --------------------------------------------------------------------------

func _animate(delta: float) -> void:
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


func _build_body() -> void:
	var flesh := Mats.flesh()
	var dark := Mats.shadow()
	var bone := Mats.bone()
	var gristle := Mats.cable()

	_rig = Node3D.new()
	add_child(_rig)

	# Two pinned legs: thick columns bolted to the deck, feet splayed forward.
	for side in [-1.0, 1.0]:
		var hip := Vector3(side * 0.64, 1.62, 0.18)
		var knee := Vector3(side * 0.78, 0.86, -0.10)
		var ankle := Vector3(side * 0.82, 0.20, -0.30)
		_limb(hip, knee, 0.25, flesh)
		_limb(knee, ankle, 0.19, flesh)
		_part_box(_rig, Vector3(0.58, 0.22, 0.92),
				Vector3(side * 0.82, 0.12, -0.34), bone)
		# A shackle and bolt at each ankle: it is pinned, not standing.
		_part_box(_rig, Vector3(0.34, 0.12, 0.34),
				Vector3(side * 0.82, 0.46, -0.18), dark)
		_part_box(_rig, Vector3(0.10, 0.30, 0.10),
				Vector3(side * 1.06, 0.15, 0.18), gristle)

	# The maw: a huge wet mass with a black opening, a bone upper lip and a
	# hinged lower jaw carrying its own row of teeth.
	var mass := _part_sphere(_rig, 1.0, Vector3(0, 2.48, 0.06),
			Vector3(1.38, 1.55, 1.05), flesh)
	mass.rotation.x = -0.10
	_part_sphere(_rig, 0.78, Vector3(0, 2.92, 0.30),
			Vector3(1.05, 0.85, 0.85), dark)
	# The black throat, proud of the face so it reads from the hall mouth.
	_part_box(_rig, Vector3(1.52, 0.74, 0.26), Vector3(0, 2.27, -0.86), dark)
	_part_box(_rig, Vector3(0.82, 0.44, 0.22), Vector3(0, 2.24, -1.00), gristle)
	# Upper lip and teeth.
	_part_box(_rig, Vector3(1.70, 0.13, 0.24), Vector3(0, 2.66, -0.91), bone)
	for i in 7:
		var x := -0.66 + 0.22 * float(i)
		_part_box(_rig, Vector3(0.10, 0.22, 0.10),
				Vector3(x, 2.54, -0.95), bone)

	_jaw = Node3D.new()
	_jaw.position = Vector3(0, 2.06, -0.56)
	_rig.add_child(_jaw)
	_part_box(_jaw, Vector3(1.46, 0.20, 0.70), Vector3(0, -0.04, -0.30), flesh)
	_part_box(_jaw, Vector3(1.30, 0.09, 0.54), Vector3(0, 0.07, -0.31), dark)
	for i in 7:
		var x := -0.54 + 0.18 * float(i)
		_part_box(_jaw, Vector3(0.09, 0.19, 0.09),
				Vector3(x, 0.15, -0.40), bone)

	# Shoulders and the two gaunt telescoping arms with cube hands.
	for i in 2:
		var shoulder := SHOULDER_L if i == 0 else SHOULDER_R
		var pivot := Node3D.new()
		pivot.position = shoulder
		_rig.add_child(pivot)
		var mesh := CSGBox3D.new()
		mesh.size = Vector3(0.17, 0.17, 1.0)
		mesh.position = Vector3(0, 0, -0.5)
		mesh.material = flesh
		pivot.add_child(mesh)
		# A long pale forearm plate along the arm, and a black knuckle band.
		var plate := CSGBox3D.new()
		plate.size = Vector3(0.22, 0.06, 0.72)
		plate.position = Vector3(0, 0.12, -0.42)
		plate.material = bone
		pivot.add_child(plate)
		var hand := CSGBox3D.new()
		hand.size = Vector3(0.55, 0.55, 0.55)
		hand.position = Vector3(0, 0, -1.0)
		hand.material = dark
		pivot.add_child(hand)
		var knuckle := CSGBox3D.new()
		knuckle.size = Vector3(0.60, 0.10, 0.16)
		knuckle.position = Vector3(0, 0.14, -0.86)
		knuckle.material = bone
		pivot.add_child(knuckle)
		_arm_pivots.append(pivot)
		_arm_meshes.append(mesh)
		_hands.append(hand)

	# The only light in the chamber: the wet orange of the mouth.
	_mouth_glow = OmniLight3D.new()
	_mouth_glow.light_color = Color(1.0, 0.26, 0.13)
	_mouth_glow.light_energy = 0.65
	_mouth_glow.omni_range = 4.4
	_mouth_glow.omni_attenuation = 1.4
	_mouth_glow.shadow_enabled = true
	_mouth_glow.position = Vector3(0, 2.25, -1.15)
	_rig.add_child(_mouth_glow)

	# A couple of bone shards caught in the shoulders, so the silhouette is
	# not just a smooth blob in the dark.
	for side in [-1.0, 1.0]:
		var shard := _part_box(_rig, Vector3(0.10, 0.46, 0.10),
				Vector3(side * 0.92, 2.86, 0.10), bone)
		shard.rotation = Vector3(0.3, 0.2 * side, 0.45 * side)


func _limb(a: Vector3, b: Vector3, radius: float, mat: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	_rig.add_child(pivot)
	pivot.position = a
	var length := a.distance_to(b)
	pivot.look_at(_rig.to_global(b), Vector3.UP)
	var mesh := CSGBox3D.new()
	mesh.size = Vector3(radius * 2.0, radius * 2.0, length)
	mesh.position = Vector3(0, 0, -length * 0.5)
	mesh.material = mat
	pivot.add_child(mesh)
	return pivot


func _part_box(parent: Node3D, size: Vector3, pos: Vector3,
		mat: StandardMaterial3D) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	parent.add_child(b)
	return b


func _part_sphere(parent: Node3D, radius: float, pos: Vector3,
		scale_v: Vector3, mat: StandardMaterial3D) -> CSGSphere3D:
	var s := CSGSphere3D.new()
	s.radius = radius
	s.position = pos
	s.scale = scale_v
	s.material = mat
	parent.add_child(s)
	return s
