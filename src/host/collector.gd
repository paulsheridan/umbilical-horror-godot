extends CharacterBody3D
## The Collector — the third body, a scavenger. It walks the annex/berth loop
## picking up the crew's scattered remains and carrying them back to the
## Processor's feeding pile. It reacts only to the player: it watches a visible
## body from far out, spits at one that comes within VOMIT_RANGE, and only
## leaves the loop to walk after one that gets inside CHASE_RANGE. It ignores
## the other monsters and is deaf to noise. Seeing it at work is the point; it
## is a witness that guards its lane, not a hunter.
##
## If it crosses a drone it does not kill it: it picks the chassis up, carries
## it to the pile with the link still live (the player can watch the whole
## ride through the video feed), and sets it down in front of the Processor.
##
## Movement is the same cheap straight-line seek as the rest of the ship, so
## `waypoints` is an authored legal loop (see main's COLLECTOR_ROUTE). It picks
## up any un-taken remains within `collect_radius`, carries up to MAX_CARRY,
## and deposits at `deposit_pos` / `deposit_node`.
##
## The body is the Kenney *Animated Characters Retro* model, scaled in
## `scenes/actors/collector.tscn` to the old 1.75 m silhouette and driven by
## its idle/walk/jump clips. The lantern and sack stay normal-sized props
## beside the scaled model; `_place_props()` pins them to the animated skeleton.

signal part_collected(part: Dictionary)
signal part_deposited(count: int)
signal bot_picked_up(bot: Node3D)
signal bot_delivered(bot: Node3D)
## The one-shot self-feed. `begun` fires when it starts walking to the maw,
## `finished` when its body is gone and only the lantern and sack remain.
signal sacrifice_begun
signal sacrifice_finished

const Mats := preload("res://src/mats.gd")

const SPEED := 0.95
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
## The Kenney walk is a normal pace. Slowing it a little and trimming the
## body's ground speed gives the heavy, plodding shamble the Collector wants.
const WALK_ANIM_SPEED := 0.9
const ANIM_BLEND := 0.18

## How the Collector reads the player. A body or chassis is acquired as
## `target` out to HEAD_TRACK_RANGE and watched whenever it has line of sight.
## The feet commit only inside CHASE_RANGE, but the spray reaches farther than
## the chase: it spits at a player it will not walk after.
const HEAD_TRACK_RANGE := 24.0
const CHASE_RANGE := 4.0
const LOSE_RANGE := 6.0
const VOMIT_RANGE := 8.0
const VOMIT_COOLDOWN := 3.5
## The attack is a one-second spray window; the attack animation is gone, so
## the whole read is the stream of small globs leaving the mouth.
const VOMIT_DURATION := 1.0
const SPRAY_INTERVAL := 0.015
const SPRAY_GRAVITY := 9.0
const SPRAY_FLIGHT_MIN := 0.38
const SPRAY_FLIGHT_MAX := 0.68
const SPRAY_SPREAD := 0.38
const SPRAY_SIZE_MIN := 0.18
const SPRAY_SIZE_MAX := 0.5
const GRAB_RANGE := 1.35
const GRAB_COOLDOWN := 2.5
## Close enough to trigger the existing bot lift (BOT_PICKUP_RADIUS = 1.0)
## while still leaving room for the body shapes to overlap harmlessly.
const PURSUE_STOP := 0.65
const VOMIT_SCENE := preload("res://scenes/actors/vomit.tscn")

## The quiet, harmless vomit between attacks: a long random gap, then a rooted
## beat where the body folds and spits at the deck ahead before walking on. It
## is deliberately slow to fire so the loop reads as a body with a bad gut
## rather than a timer. The first roll is seeded away from zero in `_ready`
## so short scripted moments never open on a vomit.
const GROUND_VOMIT_MIN := 18.0
const GROUND_VOMIT_MAX := 42.0
const GROUND_VOMIT_DURATION := 1.8
const GROUND_VOMIT_SPRAY_TIME := 0.9
const GROUND_VOMIT_AHEAD := 1.05
const GROUND_SPRAY_INTERVAL := 0.035
const GROUND_SPRAY_FLIGHT := 0.42
const GROUND_SPRAY_SPREAD := 0.16
const GROUND_SPRAY_SIZE_MIN := 0.10
const GROUND_SPRAY_SIZE_MAX := 0.26


## Layers a small forward fold onto the animated torso and head. It runs after
## the AnimationPlayer, so the walk/idle clip still drives the body underneath
## and only the bend is added. Missing bones are skipped rather than guessed.
class BendModifier extends SkeletonModifier3D:
	const SPINE_ANGLE := 0.22
	const UPPER_CHEST_ANGLE := 0.22
	const HEAD_ANGLE := 0.40

	var spine := -1
	var upper_chest := -1
	var head := -1
	var weight := 0.0

	func _process_modification() -> void:
		if weight <= 0.001:
			return
		var sk := get_skeleton()
		if sk == null:
			return
		_fold(sk, spine, SPINE_ANGLE)
		_fold(sk, upper_chest, UPPER_CHEST_ANGLE)
		_fold(sk, head, HEAD_ANGLE)

	func _fold(sk: Skeleton3D, bone: int, angle: float) -> void:
		if bone < 0:
			return
		var pose := sk.get_bone_pose_rotation(bone)
		sk.set_bone_pose_rotation(bone,
				pose * Quaternion(Vector3.RIGHT, angle * weight))

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
## The two things the Collector may fix on. Main sets the on-foot body once
## and the active chassis whenever the link moves. The nearest one within
## HEAD_TRACK_RANGE is `target`; the chase only starts inside CHASE_RANGE.
## Any visible target is head-tracked, independent of the chase and vomit
## beats, so the turn reads as attention rather than a tell.
var player_body: Node3D = null
var player_target: Node3D = null
var target: Node3D = null
var pursuing := false
## True only while `_pursue` is actively moving toward the target to pick it
## up. Body facing follows the target during that movement and during a
## mid-range spray (see `_turning_to_target`); while resting, walking the
## route, standing at PURSUE_STOP, or carrying it faces travel or holds still.
var _moving_to_pickup := false
## True on a frame where the Collector has stopped its route to square up on a
## visible player inside VOMIT_RANGE but outside CHASE_RANGE. It turns the body
## onto the target so the longer-range spray comes out of the right direction.
var _turning_to_target := false
## Stand-in attack bookkeeping, exposed for the focused suite.
var vomits := 0
var vomit_drops := 0
var grab_attempts := 0
## Walking-time ground vomit bookkeeping, exposed for the focused suite.
var ground_vomits := 0
var ground_vomit_drops := 0
var ground_bend := 0.0          # 0..1, eased pose weight for the fold
var _ground_vomit_cd := 0.0
var _ground_vomit_t := 0.0
var _ground_spray_next := 0.0

var _wp := 0
var _rest := 0.0
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _stuck_run := 0
var _rng := RandomNumberGenerator.new()
var _pickup_cd := 0.0
var _deliver_goal := -1
var _deliver_wp := -1
var _deliver_dir := 1

# One-shot sacrifice state. `consumed` persists for the session: the body does
# not return, and main never calls begin_sacrifice() twice.
var sacrificing := false
var consumed := false
## Debug vision: never lift a chassis. Main sets this on its developer toggle.
var ghosted := false
var sacrifice_pos := Vector3.ZERO
var _sacrifice_phase := 0
var _sacrifice_t := 0.0
var _sacrifice_sfx := 0.0

var _rig: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _anim_name := ""
var _hand_bone := -1
var _sack_bone := -1
var _head_bone := -1
var _look: LookAtModifier3D
var _look_target: Node3D
var _fold: BendModifier
var _sack: Node3D
var _lantern_hand: Node3D
var _lantern: OmniLight3D
var _vomit_cd := 0.0
var _vomit_t := 0.0
var _spray_next := 0.0
var _grab_cd := 0.0
var _pursuit_stuck_t := 0.0
var _pursuit_last := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	_ground_vomit_cd = _rng.randf_range(GROUND_VOMIT_MIN, GROUND_VOMIT_MAX)
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")
	floor_snap_length = 0.5
	# The body is authored in scenes/actors/collector.tscn.
	_resolve_body()
	_stuck_last = global_position


func _resolve_body() -> void:
	_rig = $Rig
	_anim = $Rig/AnimationPlayer
	_skeleton = $Rig/Model/Root/Skeleton3D
	_lantern_hand = $LanternHand
	_sack = $Sack
	_look_target = $LookTarget
	_lantern = $LanternHand/Lantern
	if _skeleton != null:
		_hand_bone = _skeleton.find_bone("RightHand")
		_sack_bone = _skeleton.find_bone("UpperChest")
		_head_bone = _skeleton.find_bone("Head")
		_build_look()
		_build_fold()
	_play_anim("idle", true)


## The imported head bone's local +Z is its face and local +Y runs up the
## skull, so the stock LookAtModifier can drive the head without hand-rolled
## bone maths. It is added at runtime because it lives inside the instanced
## Kenney skeleton.
func _build_look() -> void:
	_look = LookAtModifier3D.new()
	_look.name = "LookAt"
	_look.bone_name = "Head"
	_look.forward_axis = 4          # +Z, the face axis
	_look.primary_rotation_axis = 1 # Y, the bone's up axis
	_look.use_secondary_rotation = true
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = 70.0
	_look.secondary_limit_angle = 35.0
	_look.duration = 0.22
	_look.influence = 0.0
	_skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_target)


## The ground-vomit fold is a second skeleton modifier, added after the look so
## it layers on top of the animated pose. It does nothing until weighted in.
func _build_fold() -> void:
	_fold = BendModifier.new()
	_fold.name = "Bend"
	_fold.spine = _skeleton.find_bone("Spine")
	_fold.upper_chest = _skeleton.find_bone("UpperChest")
	_fold.head = _skeleton.find_bone("Head")
	_skeleton.add_child(_fold)


func reset() -> void:
	_wp = _nearest_wp()
	_rest = 0.0
	_stuck_t = 0.0
	_stuck_run = 0
	_stuck_last = global_position
	carrying = 0
	carried_bot = null
	_pickup_cd = 0.0
	_deliver_goal = -1
	_deliver_wp = -1
	_deliver_dir = 1
	_clear_target()
	_vomit_cd = 0.0
	_vomit_t = 0.0
	_spray_next = 0.0
	_ground_vomit_cd = _rng.randf_range(GROUND_VOMIT_MIN, GROUND_VOMIT_MAX)
	_ground_vomit_t = 0.0
	_ground_spray_next = 0.0
	ground_bend = 0.0
	if _fold != null:
		_fold.weight = 0.0
	_grab_cd = 0.0
	_pursuit_stuck_t = 0.0
	_pursuit_last = global_position
	_moving_to_pickup = false
	_turning_to_target = false
	if _rig != null:
		_rig.visible = true
	if _sack != null:
		_sack.visible = false
		_sack.scale = Vector3.ONE
	if _anim != null:
		_anim_name = ""
		_play_anim("idle", true)


## The one scripted end for the Collector. It sets down anything it is
## carrying, walks itself to the maw, and is consumed over a few audible
## seconds. Main calls this exactly once when the active drone first enters
## the Cold Hold; the body never comes back.
func begin_sacrifice(at: Vector3) -> void:
	if sacrificing or consumed:
		return
	sacrificing = true
	sacrifice_pos = at
	_sacrifice_phase = 0
	_sacrifice_t = 0.0
	_sacrifice_sfx = 0.0
	_pickup_cd = 99999.0
	_rest = 0.0
	_clear_target()
	_vomit_t = 0.0
	_spray_next = 0.0
	_ground_vomit_t = 0.0
	_ground_spray_next = 0.0
	ground_bend = 0.0
	if _fold != null:
		_fold.weight = 0.0
	# Never eat a chassis the player is riding. Set it down on the authored
	# drop mark first, exactly as a normal delivery would.
	if carried_bot != null and is_instance_valid(carried_bot):
		_drop_bot()
	sacrifice_begun.emit()


func _physics_process(delta: float) -> void:
	_moving_to_pickup = false
	_turning_to_target = false
	if consumed:
		_halt()
		return
	if sacrificing:
		_sacrifice_tick(delta)
		if not is_on_floor():
			velocity.y -= 12.0 * delta
		move_and_slide()
		_face(delta)
		_animate(delta)
		return

	_update_target(delta)
	var visible := target != null and _has_line_of_sight()
	_update_look(delta, visible)
	_vomit_cd = maxf(_vomit_cd - delta, 0.0)
	_grab_cd = maxf(_grab_cd - delta, 0.0)

	# A vomit beat is a short, rooted spray: the body stays squared up on the
	# target, and the droplets stream from the mouth across the whole window.
	# Nothing about it touches the player's movement.
	if _vomit_t > 0.0:
		_vomit_t = maxf(_vomit_t - delta, 0.0)
		_spray_next -= delta
		while _spray_next <= 0.0 and _vomit_t > 0.0:
			_spray_next += SPRAY_INTERVAL
			_spawn_spray()
		_halt()
		_face_target(delta)
		if not is_on_floor():
			velocity.y -= 12.0 * delta
		move_and_slide()
		_animate(delta)
		return

	# The walking-time ground vomit: a rooted, harmless beat. It sits before
	# the route so it wins over walking, but after the attack spray so a
	# visible player in range always gets spat at first.
	if _ground_vomit_t > 0.0:
		_ground_vomit_tick(delta)
		if not is_on_floor():
			velocity.y -= 12.0 * delta
		move_and_slide()
		_face(delta)
		_animate(delta)
		return

	if waypoints.is_empty() and target == null:
		_halt()
		_animate(delta)
		return
	if door_host != null and is_instance_valid(door_host):
		door_host.service_doors(global_position, delta, self)
	_pickup_cd = maxf(_pickup_cd - delta, 0.0)
	if carried_bot != null and not is_instance_valid(carried_bot):
		carried_bot = null
		_deliver_goal = -1
		_deliver_wp = -1

	# A bot on the shoulder is a delivery, not a chase. The body heads for the
	# Processor; target-facing is suppressed while the Collector is busy.
	var busy := _deliver_goal >= 0 or carried_bot != null
	# Inside spray range but outside chase range, with the spit ready: stop the
	# route, square up on the player and spit. Between spits it keeps working
	# the loop with its head turned. It only walks after a player who gets
	# inside CHASE_RANGE.
	var in_spray := target != null and visible and not busy \
			and _vomit_cd <= 0.0 \
			and _flat_dist(target.global_position) <= VOMIT_RANGE
	if pursuing and target != null and not busy:
		_pursue(delta)
	elif in_spray:
		_halt()
		_turning_to_target = true
	elif _rest > 0.0:
		_rest -= delta
		_halt()
	elif waypoints.is_empty():
		_halt()
	else:
		# Only a body actually walking its route winds the gut down; a long
		# chase or carry must not queue a guaranteed vomit for the moment it
		# gets back to work.
		_ground_vomit_cd = maxf(_ground_vomit_cd - delta, 0.0)
		if _can_ground_vomit():
			_start_ground_vomit()
		else:
			_walk(delta)

	_collect_nearby()
	_try_pickup_bot()
	_try_grab_target()
	# Body parts go on the pile as the loop passes it; a carried bot is a
	# deliberate detour to the same place.
	if carrying > 0 and _flat_dist(deposit_pos) < DEPOSIT_RADIUS:
		_deposit_all()
	if carried_bot != null:
		if _flat_dist(bot_drop_pos) < BOT_DROP_RADIUS:
			_drop_bot()
		else:
			_carry_bot()
	# The spray reaches farther than the chase: a visible player inside
	# VOMIT_RANGE is attacked even while the Collector holds its ground.
	if in_spray and _vomit_t <= 0.0 and _vomit_cd <= 0.0:
		_start_vomit()
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	move_and_slide()
	if not pursuing:
		_check_stuck(delta)
	# An active pickup approach and a mid-range spray both turn the body onto
	# the target. Every other beat (route walking, resting, carrying, standing
	# at PURSUE_STOP) faces travel direction or holds still.
	if _moving_to_pickup or _turning_to_target:
		_face_target(delta)
	else:
		_face(delta)
	_animate(delta)


func _sacrifice_tick(delta: float) -> void:
	_sacrifice_t += delta
	if _sacrifice_phase == 0:
		_seek(sacrifice_pos, SPEED * 1.7)
		# The walk is normally a short, visible approach. If the body is far
		# off its loop and the straight line wedges on geometry, the beat still
		# resolves: it reappears at the maw after a beat and the feeding plays
		# out. The player is in Deck B and cannot see the approach.
		if _flat_dist(sacrifice_pos) >= 0.6 and _sacrifice_t >= 8.0:
			global_position = sacrifice_pos + Vector3(0.0, 0.2, 0.0)
			velocity = Vector3.ZERO
		if _flat_dist(sacrifice_pos) < 0.6:
			_sacrifice_phase = 1
			_sacrifice_t = 0.0
			_halt()
			if _lantern != null:
				_lantern.light_energy = 0.7
			NoiseBus.emit_noise(global_position, 0.65)
		return
	_halt()
	# The lantern gutters, the sack drags across the deck, and the wet work
	# happens in three ugly bites. No cutscene: it is still a body being fed.
	if _lantern != null:
		var fade := maxf(0.0, 1.0 - _sacrifice_t / 3.6)
		_lantern.light_energy = 0.7 * fade * (0.45 + 0.55 * absf(sin(_sacrifice_t * 17.0)))
	if _sack != null:
		_sack.visible = true
		_sack.rotation.z = sin(_sacrifice_t * 9.0) * 0.18
	_sacrifice_sfx -= delta
	if _sacrifice_sfx <= 0.0 and _sacrifice_t < 3.4:
		_sacrifice_sfx = 0.85
		Sfx.play("wet_crunch", global_position, -2.0, randf_range(0.9, 1.06))
		NoiseBus.emit_noise(global_position, 0.75)
	if _sacrifice_t >= 3.6:
		_finish_sacrifice()


func _finish_sacrifice() -> void:
	if consumed:
		return
	consumed = true
	sacrificing = false
	Sfx.play("wet_snap", global_position, 0.0, 0.86)
	# The empty props stay on the deck. They live beside the rig rather than
	# under it, so hiding the body leaves the evidence behind.
	if _anim != null:
		_anim.stop()
		_anim_name = ""
	if _lantern_hand != null:
		_lantern_hand.global_position = sacrifice_pos + Vector3(0.55, 0.12, 0.0)
		_lantern_hand.rotation = Vector3.ZERO
	if _lantern != null:
		_lantern.light_energy = 0.10
		_lantern.omni_range = 2.2
	if _sack != null:
		_sack.global_position = sacrifice_pos + Vector3(-0.48, 0.12, 0.0)
		_sack.rotation = Vector3(0.0, 0.7, 0.0)
		_sack.visible = true
	if _rig != null:
		_rig.visible = false
	collision_layer = 0
	collision_mask = 0
	_halt()
	set_physics_process(false)
	sacrifice_finished.emit()


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


# --------------------------------------------------------------------------
# Player awareness: look, shamble, vomit, grab
# --------------------------------------------------------------------------

## Pick the nearest player body or active chassis. Distance only decides
## whether the Collector notices; the head turn needs line of sight (see
## `_update_look`). The feet commit at CHASE_RANGE, so the Collector watches a
## player from far out and only shambles when they come close.
func _update_target(_delta: float) -> void:
	if ghosted or sacrificing or consumed:
		_clear_target()
		return
	if target != null:
		if not is_instance_valid(target) or target.get("carried") == true:
			_clear_target()
			return
		var d := _flat_dist(target.global_position)
		if d > HEAD_TRACK_RANGE:
			_clear_target()
			return
		if d > LOSE_RANGE:
			if pursuing:
				_give_up()
			return
		if d <= CHASE_RANGE and not pursuing:
			pursuing = true
			_pursuit_last = global_position
			_pursuit_stuck_t = 0.0
		return
	target = _find_nearest_target()
	if target != null:
		_pursuit_last = global_position
		_pursuit_stuck_t = 0.0
		if _flat_dist(target.global_position) <= CHASE_RANGE:
			pursuing = true


func _find_nearest_target() -> Node3D:
	var best: Node3D = null
	var best_d := HEAD_TRACK_RANGE
	var candidates := [player_body, player_target]
	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var body := candidate as Node3D
		if body == null:
			continue
		if body.get("carried") == true:
			continue
		var d := _flat_dist(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best


func _clear_target() -> void:
	target = null
	pursuing = false
	_vomit_t = 0.0
	_spray_next = 0.0
	if _look != null:
		_look.influence = 0.0


## Stop chasing. The head may keep tracking any visible player out to
## HEAD_TRACK_RANGE; the route resumes from the nearest authored waypoint.
func _give_up() -> void:
	pursuing = false
	_vomit_t = 0.0
	_spray_next = 0.0
	_pursuit_stuck_t = 0.0
	if not waypoints.is_empty():
		_wp = _nearest_wp()
		_rest = 0.4


## The head turns at long range. A visible target inside HEAD_TRACK_RANGE is
## watched whether it moves, stands still or carries no light; only a wall
## breaks the look. This is independent of pursuit and the vomit beat, so a
## player twenty metres away is plainly noticed without being chased.
func _update_look(_delta: float, visible: bool) -> void:
	if _look == null or _look_target == null:
		return
	if target == null or not is_instance_valid(target) or not visible \
			or _flat_dist(target.global_position) > HEAD_TRACK_RANGE:
		_look.influence = 0.0
		return
	_look_target.global_position = _target_aim_point()
	_look.influence = 1.0


## A wall between the Collector's head and the target's head/body breaks the
## head turn. Physics layer 1 is the world; bodies and the fleet do not occlude.
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var from := global_position + Vector3.UP * 1.45
	var to := _target_aim_point()
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


func _target_aim_point() -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position + Vector3.UP * 1.4
	var head := target.get_node_or_null("Head") as Node3D
	if head != null:
		return head.global_position
	return target.global_position + Vector3.UP * 0.8


func _pursue(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_clear_target()
		return
	_pursuit_stuck_t += delta
	if _pursuit_stuck_t >= 0.8:
		var moved := global_position.distance_to(_pursuit_last)
		_pursuit_last = global_position
		_pursuit_stuck_t = 0.0
		if moved < 0.08 and velocity.length() > 0.2:
			_give_up()
			return
	if _flat_dist(target.global_position) > PURSUE_STOP:
		# The pickup approach turns the body onto the drone.
		_moving_to_pickup = true
		_seek(target.global_position, SPEED)
	else:
		_halt()


func _face_target(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length() > 0.1:
		var yaw := atan2(-flat.x, -flat.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))


func _start_vomit() -> void:
	if _vomit_t > 0.0 or _vomit_cd > 0.0:
		return
	_vomit_cd = VOMIT_COOLDOWN
	_vomit_t = VOMIT_DURATION
	_spray_next = 0.0
	vomits += 1
	_halt()
	Sfx.play("wet_crunch", _mouth_position(), -6.0, 1.1)


## One droplet of the stream. Each droplet is aimed at a slightly different
## point around the player and follows a ballistic arc, so the attack reads as
## a fan of liquid rather than one thrown object.
func _spawn_spray() -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := _mouth_position()
	var aim := _target_aim_point()
	var to := aim + Vector3(
			randf_range(-SPRAY_SPREAD, SPRAY_SPREAD),
			randf_range(-SPRAY_SPREAD * 0.6, SPRAY_SPREAD * 0.6),
			randf_range(-SPRAY_SPREAD, SPRAY_SPREAD))
	var flight := randf_range(SPRAY_FLIGHT_MIN, SPRAY_FLIGHT_MAX)
	var velocity := (to - from) / flight
	velocity.y += 0.5 * SPRAY_GRAVITY * flight
	var parent := get_parent()
	if parent == null:
		return
	var glob = VOMIT_SCENE.instantiate()
	parent.add_child(glob)
	glob.spray(from, velocity, flight + randf_range(0.15, 0.45),
			randf_range(SPRAY_SIZE_MIN, SPRAY_SIZE_MAX))
	if PSXLook.has_method("convert_subtree"):
		PSXLook.convert_subtree(glob)
	vomit_drops += 1


# --------------------------------------------------------------------------
# Walking-time ground vomit: a separate, harmless beat from the attack spray
# --------------------------------------------------------------------------

## Test/scripting hook: make the next walking frame roll straight into the
## ground vomit. The route conditions still have to hold.
func force_ground_vomit() -> void:
	_ground_vomit_cd = 0.0


## The ground beat only belongs to ordinary route walking: no chase, no
## carried chassis, no delivery leg, and no visible player inside attack range
## (that player is the attack spray's business, even while its cooldown runs).
func _can_ground_vomit() -> bool:
	if _ground_vomit_t > 0.0 or _ground_vomit_cd > 0.0:
		return false
	if sacrificing or consumed or pursuing:
		return false
	if carried_bot != null or _deliver_goal >= 0 or _deliver_wp >= 0:
		return false
	if waypoints.is_empty():
		return false
	if target != null and is_instance_valid(target) \
			and _flat_dist(target.global_position) <= VOMIT_RANGE \
			and _has_line_of_sight():
		return false
	return true


func _start_ground_vomit() -> void:
	_ground_vomit_cd = _rng.randf_range(GROUND_VOMIT_MIN, GROUND_VOMIT_MAX)
	_ground_vomit_t = GROUND_VOMIT_DURATION
	_ground_spray_next = 0.0
	ground_bend = 0.0
	ground_vomits += 1
	# A long halt resets the stuck clock so the beat cannot read as a wedge.
	_stuck_t = 0.0
	_stuck_last = global_position
	_halt()
	Sfx.play("wet_crunch", _mouth_position(), -10.0, 0.78)


func _ground_vomit_tick(delta: float) -> void:
	_ground_vomit_t = maxf(_ground_vomit_t - delta, 0.0)
	var elapsed := GROUND_VOMIT_DURATION - _ground_vomit_t
	# Fold in over 0.2 s, hold, then straighten over the last 0.35 s.
	var ease_in := clampf(elapsed / 0.2, 0.0, 1.0)
	var ease_out := clampf(_ground_vomit_t / 0.35, 0.0, 1.0)
	ground_bend = minf(ease_in, ease_out)
	if _fold != null:
		_fold.weight = ground_bend
	# The bend owns the neck and torso here; the player look would fight it.
	if _look != null:
		_look.influence = 0.0
	if elapsed < GROUND_VOMIT_SPRAY_TIME:
		_ground_spray_next -= delta
		while _ground_spray_next <= 0.0 and elapsed < GROUND_VOMIT_SPRAY_TIME:
			_ground_spray_next += GROUND_SPRAY_INTERVAL
			_spawn_ground_vomit()
	if _ground_vomit_t <= 0.0:
		ground_bend = 0.0
		if _fold != null:
			_fold.weight = 0.0
	_halt()


## One glob of the ground arc. The Collector is facing its travel direction, so
## the spill is aimed at a point on the deck just ahead of the feet, never at
## the player. Parenting and PSX conversion mirror the attack spray exactly;
## the droplet frees itself, so no puddle or collision is left behind.
func _spawn_ground_vomit() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()
	var ahead := GROUND_VOMIT_AHEAD + randf_range(-0.18, 0.18)
	var to := global_position + forward * ahead
	to.y = global_position.y + 0.02
	to += Vector3(randf_range(-GROUND_SPRAY_SPREAD, GROUND_SPRAY_SPREAD), 0.0,
			randf_range(-GROUND_SPRAY_SPREAD, GROUND_SPRAY_SPREAD))
	var from := _mouth_position()
	var flight := GROUND_SPRAY_FLIGHT * randf_range(0.85, 1.15)
	var velocity := (to - from) / flight
	velocity.y += 0.5 * SPRAY_GRAVITY * flight
	var glob = VOMIT_SCENE.instantiate()
	parent.add_child(glob)
	glob.spray(from, velocity, flight + randf_range(0.05, 0.18),
			randf_range(GROUND_SPRAY_SIZE_MIN, GROUND_SPRAY_SIZE_MAX))
	if PSXLook.has_method("convert_subtree"):
		PSXLook.convert_subtree(glob)
	ground_vomit_drops += 1


func _mouth_position() -> Vector3:
	if _skeleton != null and _head_bone >= 0:
		var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)
		var forward := head.basis.orthonormalized().z
		return head.origin + forward * 0.22 + Vector3.UP * -0.03
	return global_position + global_transform.basis * Vector3(0.0, 1.45, -0.35)


## A chassis target is handled by the existing lift. The walking player cannot
## be carried without taking their body away, so this is the visible attempt:
## a thud with no control loss and no attack animation.
func _try_grab_target() -> void:
	if target == null or not is_instance_valid(target) or target != player_body:
		return
	if _vomit_t > 0.0 or _grab_cd > 0.0:
		return
	if _flat_dist(target.global_position) > GRAB_RANGE:
		return
	_grab_cd = GRAB_COOLDOWN
	grab_attempts += 1
	_halt()
	Sfx.play("thud", global_position, -5.0, 0.85)


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
	if ghosted:
		return
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
		if b == target:
			grab_attempts += 1
			_clear_target()
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
	# Turn on travel only. Falling velocity must not count as facing: with no
	# horizontal motion atan2(-0.0, -0.0) reads as a half-turn and spun the
	# body on spawn before it had walked anywhere.
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.08:
		var yaw := atan2(-flat.x, -flat.y)
		rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 5.0, 1.0))


func _animate(_delta: float) -> void:
	# The Kenney clips carry the whole body: idle while resting, a slowed walk
	# on the loop, jump only when the body is genuinely off the deck. The vomit
	# spray has no attack clip; the body simply stands under the stream.
	var want := "idle"
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed > 0.1:
		want = "walk"
	if not sacrificing and not is_on_floor() and velocity.y < -0.9:
		want = "jump"
	if want == "jump" and _anim != null and _anim_name == "jump" \
			and not _anim.is_playing():
		_anim.play("jump", 0.08)
	else:
		_play_anim(want)
	_place_props()


func _play_anim(name: String, force := false) -> void:
	if _anim == null or (not force and _anim_name == name):
		return
	if not _anim.has_animation(name):
		return
	_anim_name = name
	_anim.speed_scale = WALK_ANIM_SPEED if name == "walk" else 1.0
	_anim.play(name, ANIM_BLEND)


## The lantern and sack are normal-sized props beside the scaled model, so
## they are pinned to the animated skeleton every frame instead of inheriting
## its 47x import scale under a bone attachment.
func _place_props() -> void:
	if _lantern_hand != null and _skeleton != null and _hand_bone >= 0:
		var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone)
		_lantern_hand.global_position = hand.origin + Vector3(0.0, -0.04, 0.0)
	if _sack != null and _sack.visible and _skeleton != null and _sack_bone >= 0:
		var chest := _skeleton.global_transform * _skeleton.get_bone_global_pose(_sack_bone)
		_sack.global_position = chest.origin \
				+ global_transform.basis * Vector3(0.0, 0.08, 0.20)
		_sack.rotation.y = rotation.y
