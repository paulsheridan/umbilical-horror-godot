extends CharacterBody3D
## The Collector — the third body, a scavenger. It is not a hunter: it walks
## the annex/berth loop picking up the crew's scattered remains and carrying
## them back to the Processor's feeding pile. It never chases the drone, never
## reacts to other monsters, and is deaf to noise. Seeing it at work is the
## point; it is a witness, not a threat.
##
## If it crosses a drone it does not kill it: it picks the chassis up, carries
## it to the pile with the link still live (the player can watch the whole
## ride through the video feed), and sets it down in front of the Processor.
##
## Movement is the same cheap straight-line seek as the rest of the ship, so
## `waypoints` is an authored legal loop (see main's COLLECTOR_ROUTE). It picks
## up any un-taken remains within `collect_radius`, carries up to MAX_CARRY,
## and deposits at `deposit_pos` / `deposit_node`.

signal part_collected(part: Dictionary)
signal part_deposited(count: int)
signal bot_picked_up(bot: Node3D)
signal bot_delivered(bot: Node3D)

const Mats := preload("res://src/mats.gd")

const SPEED := 1.05
const ARRIVE := 0.55
const COLLECT_RADIUS := 1.15
const DEPOSIT_RADIUS := 1.1
const MAX_CARRY := 4
const REST_MIN := 0.5
const REST_MAX := 1.3
const BOT_PICKUP_RADIUS := 1.0
const BOT_DROP_RADIUS := 0.45
const BOT_DROP_COOLDOWN := 6.0
const BOT_CARRY_Y := 0.95
const BOT_CARRY_Z := -0.55

var waypoints: Array = []
var remains: Array = []          # [{node, pos, taken}] shared with the ship
var deposit_pos := Vector3.ZERO
var deposit_node: Node3D = null
## Live drone chassis. main hands over its `drones` array reference, so the
## Collector always sees the current fleet.
var bots: Array = []
var carried_bot = null
## Where a carried chassis is set down (the Processor pile's hall side).
var bot_drop_pos := Vector3.ZERO
## The ship node, so the Collector can open the berth-wing cabin doors itself.
var door_host = null
var carrying := 0
var deposited := 0
## Kept off the radar: the Collector makes no noise and reads as nothing.
var radar_blips := false

var _wp := 0
var _rest := 0.0
var _gait := 0.0
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _stuck_run := 0
var _rng := RandomNumberGenerator.new()
var _pickup_cd := 0.0
var _deliver_goal := -1
var _deliver_wp := -1
var _deliver_dir := 1

var _rig: Node3D
var _hips: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _sack: Node3D
var _lantern: OmniLight3D


func _ready() -> void:
	_rng.randomize()
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")
	floor_snap_length = 0.5

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.6
	col.shape = capsule
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	_build_body()
	_stuck_last = global_position


func reset() -> void:
	_wp = _nearest_wp()
	_rest = 0.0
	_stuck_t = 0.0
	_stuck_run = 0
	_stuck_last = global_position
	_gait = 0.0
	carrying = 0
	carried_bot = null
	_pickup_cd = 0.0
	_deliver_goal = -1
	_deliver_wp = -1
	_deliver_dir = 1
	if _sack != null:
		_sack.visible = false


func _physics_process(delta: float) -> void:
	if waypoints.is_empty():
		_halt()
		return
	if door_host != null and is_instance_valid(door_host):
		door_host.service_doors(global_position, delta, self)
	_pickup_cd = maxf(_pickup_cd - delta, 0.0)
	if carried_bot != null and not is_instance_valid(carried_bot):
		carried_bot = null
		_deliver_goal = -1
		_deliver_wp = -1
	if _rest > 0.0:
		_rest -= delta
		_halt()
	else:
		_walk(delta)
	_collect_nearby()
	_try_pickup_bot()
	# Body parts go on the pile as the loop passes it; a carried bot is a
	# deliberate detour to the same place.
	if carrying > 0 and _flat_dist(deposit_pos) < DEPOSIT_RADIUS:
		_deposit_all()
	if carried_bot != null:
		if _flat_dist(bot_drop_pos) < BOT_DROP_RADIUS:
			_drop_bot()
		else:
			_carry_bot()
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	move_and_slide()
	_check_stuck(delta)
	_face(delta)
	_animate(delta)


## Walk the authored loop, or the legal slice of it that leads to the pile
## when the Collector is carrying something the Processor should get.
func _walk(_delta: float) -> void:
	if _deliver_goal >= 0:
		if _deliver_wp < 0:
			_start_delivery_leg()
		var target: Vector3 = waypoints[_deliver_wp]
		_seek(target, SPEED)
		if _flat_dist(target) < ARRIVE:
			if _deliver_wp == _deliver_goal:
				_finish_delivery()
			else:
				_deliver_wp = _wrap(_deliver_wp + _deliver_dir)
		return
	var target: Vector3 = waypoints[_wp]
	_seek(target, SPEED)
	if _flat_dist(target) < ARRIVE:
		_wp = _wrap(_wp + 1)
		_rest = _rng.randf_range(REST_MIN, REST_MAX)


func _wrap(i: int) -> int:
	var n := waypoints.size()
	if n <= 0:
		return 0
	return ((i % n) + n) % n


func _nearest_wp_to(target: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in waypoints.size():
		var wp: Vector3 = waypoints[i]
		var d := Vector2(wp.x - target.x, wp.z - target.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Begin routing to the pile through the authored loop. The route visits the
## pile, so following waypoints is always legal; pick the shorter direction.
func _begin_delivery() -> void:
	if waypoints.is_empty() or _deliver_goal >= 0:
		return
	_deliver_goal = _nearest_wp_to(deposit_pos)
	_deliver_wp = -1
	_deliver_dir = 1


func _start_delivery_leg() -> void:
	var n := waypoints.size()
	if n <= 0:
		_deliver_goal = -1
		return
	# Finish the leg already in progress first; the next hops are always
	# adjacent waypoints, so the Collector never cuts a corner through a wall.
	if _wp == _deliver_goal:
		_deliver_dir = 1
		_deliver_wp = _deliver_goal
		return
	var fwd := ((_deliver_goal - _wp) % n + n) % n
	var back := ((_wp - _deliver_goal) % n + n) % n
	_deliver_dir = 1 if fwd <= back else -1
	_deliver_wp = _wp


func _finish_delivery() -> void:
	if carrying > 0:
		_deposit_all()
	if carried_bot != null:
		_drop_bot()
	_wp = _deliver_goal if _deliver_goal >= 0 else _wp
	_deliver_goal = -1
	_deliver_wp = -1
	_rest = 0.8


## Desperate command hook for tests / scripted moments.
func force_wp(index: int) -> void:
	if waypoints.is_empty():
		return
	_wp = clampi(index, 0, waypoints.size() - 1)
	_rest = 0.0
	_deliver_goal = -1
	_deliver_wp = -1


func _collect_nearby() -> void:
	if carrying >= MAX_CARRY:
		return
	for part in remains:
		if part.get("taken", false):
			continue
		var need := 0.0
		if part["node"] != null and is_instance_valid(part["node"]):
			need = global_position.distance_to(part["node"].global_position)
		else:
			need = _flat_dist(part["pos"])
		if need > COLLECT_RADIUS:
			continue
		part["taken"] = true
		if part["node"] != null and is_instance_valid(part["node"]):
			part["node"].visible = false
		carrying += 1
		if _sack != null:
			_sack.visible = true
			_sack.scale = Vector3.ONE * (0.85 + 0.12 * float(carrying))
		part_collected.emit(part)
		if carrying >= MAX_CARRY:
			_begin_delivery()
		return


## If the loop crosses a live chassis, lift it. The chassis is frozen, not
## killed: its link and camera stay up, so the player can ride along.
func _try_pickup_bot() -> void:
	if carried_bot != null or _pickup_cd > 0.0:
		return
	for b in bots:
		if b == null or not is_instance_valid(b):
			continue
		if b.get("carried") == true:
			continue
		if b.global_position.distance_to(global_position) > BOT_PICKUP_RADIUS:
			continue
		carried_bot = b
		b.carried = true
		b.velocity = Vector3.ZERO
		_rest = 0.25
		_begin_delivery()
		bot_picked_up.emit(b)
		Sfx.play("thud", global_position, -5.0)
		return


## Hold the carried chassis in front of the body, facing back at the Collector.
## Its own physics is frozen while `carried` is true; this is the only mover.
func _carry_bot() -> void:
	if carried_bot == null or not is_instance_valid(carried_bot):
		return
	var anchor := global_transform.basis * Vector3(0.0, BOT_CARRY_Y, BOT_CARRY_Z)
	carried_bot.global_position = global_position + anchor
	carried_bot.rotation.y = rotation.y + PI


func _drop_bot() -> void:
	var b = carried_bot
	carried_bot = null
	if b != null and is_instance_valid(b):
		b.global_position = Vector3(bot_drop_pos.x, bot_drop_pos.y, bot_drop_pos.z)
		b.rotation.y = PI * 0.5      # face west, down the hall, away from the mouth
		b.velocity = Vector3.ZERO
		b.carried = false
		bot_delivered.emit(b)
	_pickup_cd = BOT_DROP_COOLDOWN
	_rest = 1.0


## Teardown path: the fleet is about to be freed, so let go without trying to
## place a node that is on its way out.
func release_carried() -> void:
	if carried_bot != null and is_instance_valid(carried_bot):
		carried_bot.carried = false
	carried_bot = null
	_pickup_cd = 0.0
	_deliver_goal = -1
	_deliver_wp = -1


func _deposit_all() -> void:
	if carrying <= 0:
		return
	if deposit_node != null and is_instance_valid(deposit_node):
		for i in carrying:
			var bone := CSGBox3D.new()
			bone.size = Vector3(0.20, 0.075, 0.10)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.0, 0.35)
			bone.position = Vector3(cos(a) * r, 0.10 + 0.05 * float(i),
					sin(a) * r)
			bone.rotation = Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))
			bone.material = Mats.bone()
			bone.use_collision = false
			deposit_node.add_child(bone)
	deposited += carrying
	var n := carrying
	carrying = 0
	if _sack != null:
		_sack.visible = false
	part_deposited.emit(n)


func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _seek(target: Vector3, speed: float) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() > 0.30:
		var dir := flat.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		_halt()


func _flat_dist(target: Vector3) -> float:
	var flat := target - global_position
	flat.y = 0.0
	return flat.length()


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
	_stuck_t += delta
	if _stuck_t < 0.8:
		return
	_stuck_t = 0.0
	var moved := global_position.distance_to(_stuck_last)
	_stuck_last = global_position
	if moved < 0.10 and velocity.length() > 0.2:
		_stuck_run += 1
		if _stuck_run >= 2:
			_stuck_run = 0
			if _deliver_goal >= 0 and _deliver_wp >= 0:
				_deliver_wp = _wrap(_deliver_wp + _deliver_dir)
			else:
				_wp = _wrap(_wp + 1)
	else:
		_stuck_run = 0


func _face(delta: float) -> void:
	if velocity.length() > 0.08:
		var yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))


func _animate(delta: float) -> void:
	var moving := velocity.length()
	_gait += delta * (6.0 if moving > 0.1 else 1.5)
	if _hips != null:
		_hips.position.y = 0.86 + sin(_gait * 1.7) * (0.025 if moving > 0.1 else 0.006)
	if _arm_l != null:
		_arm_l.rotation.x = sin(_gait) * 0.28
	if _arm_r != null:
		_arm_r.rotation.x = -sin(_gait) * 0.22
	if _leg_l != null:
		_leg_l.rotation.x = sin(_gait) * 0.38
	if _leg_r != null:
		_leg_r.rotation.x = -sin(_gait) * 0.38
	if _head != null:
		_head.rotation.x = 0.12 + sin(_gait * 0.6) * 0.05
	if _sack != null and _sack.visible:
		_sack.rotation.z = sin(_gait * 0.8) * 0.06


func _build_body() -> void:
	var pale := Mats.bone()
	var dark := Mats.shadow()
	var cloth := Mats.paper()
	var amber := Mats.amber()

	_rig = Node3D.new()
	add_child(_rig)

	_hips = Node3D.new()
	_hips.position = Vector3(0, 0.86, 0)
	_rig.add_child(_hips)

	# Hunched trunk and a low, forward head: it is always looking at the floor.
	var torso := CSGCylinder3D.new()
	torso.radius = 0.20
	torso.height = 0.78
	torso.position = Vector3(0, 0.33, 0.02)
	torso.rotation = Vector3(-0.22, 0, 0)
	torso.material = cloth
	_hips.add_child(torso)
	var rib := CSGBox3D.new()
	rib.size = Vector3(0.30, 0.06, 0.05)
	rib.position = Vector3(0, 0.26, -0.20)
	rib.material = pale
	_hips.add_child(rib)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.72, -0.10)
	_hips.add_child(_head)
	var skull := CSGSphere3D.new()
	skull.radius = 0.145
	skull.scale = Vector3(0.9, 1.2, 1.0)
	skull.material = pale
	_head.add_child(skull)
	var jaw := CSGBox3D.new()
	jaw.size = Vector3(0.13, 0.16, 0.07)
	jaw.position = Vector3(0, -0.08, -0.12)
	jaw.material = dark
	_head.add_child(jaw)

	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.24, 0.50, -0.02)
		_hips.add_child(arm)
		var upper := CSGBox3D.new()
		upper.size = Vector3(0.09, 0.56, 0.09)
		upper.position = Vector3(0, -0.28, 0)
		upper.material = pale
		arm.add_child(upper)
		var hand := CSGBox3D.new()
		hand.size = Vector3(0.11, 0.12, 0.13)
		hand.position = Vector3(0, -0.60, -0.03)
		hand.material = dark
		arm.add_child(hand)
		if side < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm

	# It drags a lamp low, so the floor and the parts are always lit.
	var lantern_hand := Node3D.new()
	lantern_hand.position = Vector3(0.24, 0.14, -0.08)
	_hips.add_child(lantern_hand)
	var cage := CSGSphere3D.new()
	cage.radius = 0.09
	cage.material = amber
	lantern_hand.add_child(cage)
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color(1.0, 0.62, 0.30)
	_lantern.light_energy = 0.55
	_lantern.omni_range = 3.6
	_lantern.omni_attenuation = 1.6
	_lantern.shadow_enabled = true
	lantern_hand.add_child(_lantern)

	# Legs: short and bent, so the whole body is a low silhouette.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.12, 0.62, 0)
		_hips.add_child(leg)
		var shin := CSGBox3D.new()
		shin.size = Vector3(0.11, 0.62, 0.11)
		shin.position = Vector3(0, -0.31, 0)
		shin.material = dark
		leg.add_child(shin)
		var foot := CSGBox3D.new()
		foot.size = Vector3(0.13, 0.08, 0.26)
		foot.position = Vector3(0, -0.60, -0.07)
		foot.material = pale
		leg.add_child(foot)
		if side < 0.0:
			_leg_l = leg
		else:
			_leg_r = leg

	# The drag sack: a heavy lump on its back, visible only while carrying.
	_sack = Node3D.new()
	_sack.position = Vector3(0, 0.34, 0.24)
	_hips.add_child(_sack)
	var bag := CSGSphere3D.new()
	bag.radius = 0.22
	bag.scale = Vector3(0.9, 1.15, 0.95)
	bag.material = cloth
	_sack.add_child(bag)
	var knot := CSGCylinder3D.new()
	knot.radius = 0.05
	knot.height = 0.14
	knot.position = Vector3(0, 0.24, 0)
	knot.material = dark
	_sack.add_child(knot)
	_sack.visible = false
