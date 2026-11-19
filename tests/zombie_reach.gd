extends Node3D
## Focused probe for the chase reach: a Host in its sight pursuit and a
## Stalker in its chase both hold their hands out toward the drone while the
## legs keep running the authored locomotion. Every other state has to leave
## the arms to the authored clip.
## The Watcher — the zombie that plants instead of attacking — reaches only
## while it is still closing; planted at its stand-off its arms hang at the
## authored clip.
##
## Run: godot --headless --path . res://tests/zombie_reach.tscn

const HOST_SCENE := preload("res://scenes/actors/host.tscn")
const STALKER_SCENE := preload("res://scenes/actors/stalker.tscn")
const WATCHER_SCENE := preload("res://scenes/actors/watcher.tscn")

var host: CharacterBody3D
var stalker: CharacterBody3D
var drone: CharacterBody3D
var skeleton: Skeleton3D
var _failed := false
var _wcaught := false


## The hosts read exactly these three properties off the bound drone.
class DummyDrone extends CharacterBody3D:
	var flashlight_installed := false
	var flashlight_on := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _bone_world(node: Skeleton3D, bone: String) -> Vector3:
	var idx := node.find_bone(bone)
	if idx < 0:
		return Vector3.ZERO
	return node.global_transform * node.get_bone_global_pose(idx).origin


## A skeleton applies its modifiers in a deferred pass, so the final, reached
## pose is only readable the moment the modifier reports it. Elsewhere
## get_bone_global_pose() hands back the animated base pose.
func _settled_hand(node: Skeleton3D, modifier: SkeletonModifier3D,
		bone: String) -> Vector3:
	await modifier.modification_processed
	return _bone_world(node, bone)


## Hand position in the body's own space, relative to the chest. Comparing
## offsets cancels the body's travel, so a return to the clip can be checked
## even though the host walked forward during the stalk.
func _hand_offset(node: Skeleton3D, body: Node3D, bone: String) -> Vector3:
	var inv: Transform3D = body.global_transform.affine_inverse()
	return inv * _bone_world(node, bone) - inv * _bone_world(node, "Chest")


## Sample the authored clip at a fixed phase. The idle sway moves the hands a
## few centimetres, so a before/after comparison has to pin the clip first or
## it measures the sway phase instead of the reach.
func _clip_hands(seconds: float) -> Array:
	host.set_physics_process(false)
	host._anim.speed_scale = 0.0
	host._anim.seek(seconds, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var hands := [_hand_offset(skeleton, host, "LeftHand"),
			_hand_offset(skeleton, host, "RightHand")]
	host._anim.speed_scale = 1.0
	host.set_physics_process(true)
	return hands


func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)

	drone = DummyDrone.new()
	add_child(drone)
	drone.global_position = Vector3(0, 0.32, -8.5)
	drone.velocity = Vector3.ZERO

	host = HOST_SCENE.instantiate()
	add_child(host)
	host.global_position = Vector3(0, 0.2, 0)
	host.rotation.y = 0.0
	host.waypoints = []
	host.drone = drone
	host.reset()
	skeleton = host._skeleton
	await _wait(20)

	# --- Idle / patrol: the authored clip owns the arms ---------------------
	var patrol_hands := await _clip_hands(0.0)
	var patrol_l: Vector3 = patrol_hands[0]
	var patrol_r: Vector3 = patrol_hands[1]
	var patrol_dist_l := _bone_world(skeleton, "LeftHand").distance_to(drone.global_position)
	var patrol_dist_r := _bone_world(skeleton, "RightHand").distance_to(drone.global_position)
	_check(host.reach_weight < 0.1, "a patrolling host does not reach")

	# --- A noise hunt walks with its arms down ------------------------------
	host.force_hunt(Vector3(4, 0.2, -9))
	await _wait(25)
	_check(host.state == host.State.HUNT and host.reach_weight < 0.1,
			"a host hunting a noise does not reach")
	_check(Vector2(host.velocity.x, host.velocity.z).length() > 0.15,
			"the noise hunt is actually walking")
	host._give_up()
	host._halt()

	# --- Stalk: running at a visible drone raises both hands ----------------
	host.global_position = Vector3(0, 0.2, 0)
	host.rotation.y = 0.0
	host.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -8.5)
	drone.velocity = Vector3(0, 0, -0.5)
	host.force_stalk(drone.global_position)
	await _wait(30)
	_check(host.reach_weight > 0.6, "a stalking host reaches for the drone")
	var stalk_l := await _settled_hand(skeleton, host._reach, "LeftHand")
	var stalk_r := await _settled_hand(skeleton, host._reach, "RightHand")
	var chest_local: Vector3 = host.global_transform.affine_inverse() \
			* _bone_world(skeleton, "Chest")
	var hand_l_local: Vector3 = host.global_transform.affine_inverse() * stalk_l
	var hand_r_local: Vector3 = host.global_transform.affine_inverse() * stalk_r
	_check(stalk_l.distance_to(drone.global_position) < patrol_dist_l - 0.15,
			"the left hand reaches toward the drone")
	_check(stalk_r.distance_to(drone.global_position) < patrol_dist_r - 0.15,
			"the right hand reaches toward the drone")
	_check(hand_l_local.z < chest_local.z and hand_r_local.z < chest_local.z,
			"both hands are held out in front of the chest")
	_check(host._anim_name == "run", "the legs keep the run clip while the arms reach")
	for pair in [["LeftArm", stalk_l], ["RightArm", stalk_r]]:
		var arm_pos := _bone_world(skeleton, str(pair[0]))
		var hand: Vector3 = pair[1]
		var to_drone: Vector3 = (drone.global_position + Vector3.UP * 0.45
				- arm_pos).normalized()
		_check(to_drone.dot((hand - arm_pos).normalized()) > 0.9,
				"the %s aims at the drone" % pair[0])

	# --- The fixed host closes: no hold distance any more -------------------
	drone.global_position = host.global_position + Vector3(0, 0.12, -5.0)
	await _wait(25)
	var close_gap: float = host.global_position.distance_to(drone.global_position)
	_check(close_gap < 4.6, "a stalking host closes on a drone 5 m out (%.1f m)" % close_gap)
	_check(host.state == host.State.STALK and host._sees and host.reach_weight > 0.6,
			"a stalking host keeps its hands out while it closes")
	_check(host._anim_name == "run", "the closing host keeps the run clip")

	# --- Loss of the drone: the arms drop back to the clip ------------------
	host._give_up()
	host._halt()
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(0, 0.32, -26.0)
	await _wait(40)
	var back_hands := await _clip_hands(0.0)
	var back_l: Vector3 = back_hands[0]
	var back_r: Vector3 = back_hands[1]
	_check(host.reach_weight < 0.1, "a host that lost the drone stops reaching")
	_check((back_l - patrol_l).length() < 0.08 and (back_r - patrol_r).length() < 0.08,
			"the hands return to their authored clip")

	# --- Ghosted debug bodies never reach ----------------------------------
	host.ghosted = true
	drone.velocity = Vector3(0, 0, -0.5)
	drone.global_position = Vector3(0, 0.32, -8.5)
	host.force_stalk(drone.global_position)
	await _wait(20)
	_check(host.reach_weight < 0.1, "a ghosted host never reaches")
	host.ghosted = false

	# --- Watcher: it plants at the stand-off and watches, arms down ---------
	host.drone = null
	host._give_up()
	var watcher = WATCHER_SCENE.instantiate()
	add_child(watcher)
	watcher.global_position = Vector3(-8, 0.2, 4)
	watcher.rotation.y = 0.0
	watcher.waypoints = []
	watcher.drone = drone
	watcher.reset()
	_wcaught = false
	watcher.drone_caught.connect(func() -> void: _wcaught = true)
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -9.0)
	drone.velocity = Vector3(0, 0, -0.5)
	watcher.force_stalk(drone.global_position)
	await _wait(30)
	_check(watcher.state == watcher.State.STALK and watcher.reach_weight > 0.6,
			"an approaching watcher reaches while it closes")
	await _wait(90)
	var planted_gap: float = watcher.global_position.distance_to(drone.global_position)
	_check(Vector2(watcher.velocity.x, watcher.velocity.z).length() < 0.15,
			"a watcher plants at the stand-off instead of attacking")
	_check(absf(planted_gap - watcher.WATCH_STANDOFF) < 1.0,
			"the stand-off holds the drone at %.1f m" % planted_gap)
	_check(watcher.state == watcher.State.STALK and watcher._sees
			and watcher.reach_weight < 0.1,
			"a planted watcher watches with its arms down")
	_check(watcher._anim_name == "idle", "the planted watcher plays the idle clip")
	var planted_at: Vector3 = watcher.global_position

	# The player approaches: it does not move.
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -2.5)
	await _wait(40)
	_check(watcher.global_position.distance_to(planted_at) < 0.15
			and Vector2(watcher.velocity.x, watcher.velocity.z).length() < 0.15,
			"a watcher does not move when the player approaches")
	_check(watcher.state == watcher.State.STALK and watcher._sees,
			"the approached watcher keeps watching")

	# Too close: contact is the fail state.
	drone.global_position = watcher.global_position + Vector3(0, 0.12, -0.8)
	await _wait(12)
	_check(_wcaught, "contact inside catch range still kills")
	watcher.drone = null

	# --- Stalker: the hunt pose and the spook rear --------------------------
	stalker = STALKER_SCENE.instantiate()
	add_child(stalker)
	stalker.global_position = Vector3(8, 0.2, 4)
	stalker.rotation.y = 0.0
	stalker.waypoints = []
	stalker.hide_spots = []
	stalker.ambush_spots = []
	stalker.drone = drone
	stalker.reset()
	await _wait(2)
	drone.global_position = Vector3(8, 0.32, -2.0)
	drone.velocity = Vector3(0, 0, -0.5)
	stalker.force_chase()
	stalker._sees = true
	await _wait(25)
	_check(stalker.arm_reach > 0.3 and stalker._rig.hunt_pose > 0.25,
			"a prowling stalker carries its raised hunt forelegs")

	# It drops the pose when the hunt ends.
	drone.velocity = Vector3.ZERO
	drone.global_position = Vector3(8, 0.32, -26.0)
	stalker._enter_patrol()
	await _wait(30)
	_check(stalker.state == stalker.State.PATROL and stalker.arm_reach < 0.1,
			"a stalker that lost the hunt drops its forelegs")

	# The spook hold rears the graspers high.
	stalker.state = stalker.State.PLAY
	stalker._play_phase = stalker.PLAY_PHASE_HOLD
	stalker._animate(0.2)
	stalker._animate(0.2)
	_check(stalker._rig.foreleg_pitch() < -0.6,
			"the spook hold rears the forelegs")

	print("ZOMBIE REACH", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)
