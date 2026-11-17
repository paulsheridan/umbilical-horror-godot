extends Node3D
## Focused probe for the Collector: loud doors, pickup/deposit, bot carrying,
## player/drone awareness, line of sight and the give-up ring. Level geometry
## is not asserted here so the ship can be relaid out freely.
##
## Run: godot --headless --path . res://tests/collector_ai.tscn

const SHIP_SCENE := preload("res://scenes/level/ship.tscn")
const COLLECTOR_SCENE := preload("res://scenes/actors/collector.tscn")

class DummyBot extends CharacterBody3D:
	var carried := false
	var bot_index := 0

var ship: Node3D
var collector: CharacterBody3D
var _failed := false
var _bot_delivered := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _count_type(node: Node, type_name: String) -> int:
	var n := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		n += _count_type(child, type_name)
	return n


func _count_vomit(node: Node) -> int:
	var script = node.get_script()
	var n := 0
	if script != null and str(script.resource_path).ends_with("vomit.gd"):
		n += 1
	for child in node.get_children():
		n += _count_vomit(child)
	return n


func _run() -> void:
	ship = SHIP_SCENE.instantiate()
	add_child(ship)
	await _wait(2)

	# --- Layout data -------------------------------------------------------
	_check(ship.collector_pile != null, "the Collector's deposit node exists")
	_check(ship.collector_pile.global_position.distance_to(ship.COLLECTOR_DEPOSIT) < 0.1,
			"deposit node sits on the movable deposit constant")
	# --- Loud doors --------------------------------------------------------
	NoiseBus.clear()
	var door = ship.loud_doors[0]
	var start_x: float = door["node"].position.x
	var trigger: Vector3 = door["trigger"]
	ship.service_doors(trigger, 0.016)
	_check(door["opening"], "a nearby drone triggers the cabin door")
	_check(NoiseBus.count > 0, "opening a cabin door posts noise")
	for _i in 90:
		ship.service_doors(trigger, 1.0 / 60.0)
	_check(door["node"].position.x > start_x + 0.9, "the door slides open")
	_check(door["settled"], "the door settles open")

	# --- Collector ---------------------------------------------------------
	collector = COLLECTOR_SCENE.instantiate()
	add_child(collector)
	collector.global_position = Vector3(0, 0.2, 0)
	await _wait(1)
	_check(collector._rig != null and collector._sack != null
			and collector._skeleton != null and collector._anim != null,
			"the Collector has an animated body and a drag sack")
	_check(collector.is_in_group("hosts"), "the Collector is in the host group")
	_check(not collector.radar_blips, "the Collector makes no radar blips")
	_check(not collector.has_signal("drone_caught"),
			"the Collector has no kill signal")
	_check(not collector.has_method("_on_noise"),
			"the Collector is deaf to noise")

	# It can open a cabin door for itself (the nest door starts closed).
	collector.door_host = ship
	collector.global_position = Vector3(19.8, 0.2, -11.5)
	collector.waypoints = [Vector3(19.8, 0.2, -8.0)]
	collector.remains = []
	collector.reset()
	for _i in 45:
		await get_tree().physics_frame
	_check(ship.loud_doors[3]["opening"],
			"the Collector opens the ossuary door itself")

	# Pickup and deposit in a bare corner, away from the ship's own remains.
	var part := Node3D.new()
	part.position = Vector3(0, 0.05, 0)
	add_child(part)
	var deposit := Node3D.new()
	deposit.position = Vector3(0, 0, 2.0)
	add_child(deposit)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.remains = [{"node": part, "pos": part.position, "taken": false}]
	collector.deposit_node = deposit
	collector.deposit_pos = deposit.position
	collector.waypoints = [Vector3(0, 0, 2.0)]
	collector.reset()
	var picked := false
	var delivered := false
	for _i in 240:
		await get_tree().physics_frame
		if collector.carrying > 0:
			picked = true
		if collector.deposited > 0:
			delivered = true
			break
	_check(picked, "the Collector picks up a nearby part")
	_check(not part.visible, "the picked-up part leaves the floor")
	_check(delivered and collector.carrying == 0,
			"the Collector deposits the part at its nest")
	_check(deposit.get_child_count() > 0, "deposited parts build the nest pile")

	# Delivery routing follows the authored loop to the deposit, not to
	# whichever waypoint happens to be closest to the Collector.
	collector.waypoints = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)]
	_check(collector._nearest_wp_to(Vector3(18, 0, 0)) == 2,
			"delivery picks the waypoint nearest the deposit")
	collector._wp = 1
	collector._deliver_goal = 2
	collector._deliver_wp = -1
	collector._start_delivery_leg()
	_check(collector._deliver_wp == 1,
			"delivery finishes the leg already in progress")
	collector._wp = 2
	collector._deliver_goal = 2
	collector._deliver_wp = -1
	collector._start_delivery_leg()
	_check(collector._deliver_wp == 2,
			"delivery completes when already heading to the pile")

	# --- Bot carrying ------------------------------------------------------
	# The Collector lifts a chassis instead of killing it. The body is frozen
	# in the carry (self-movement suspended), delivered to the Processor's
	# hall side, and still valid afterwards: nothing auto-disconnects.
	var bot := DummyBot.new()
	add_child(bot)
	bot.global_position = Vector3(0, 0.2, 0)
	bot.velocity = Vector3(3.0, 0.0, 0.0)   # it was driving when found
	collector.bots = [bot]
	collector.bot_drop_pos = Vector3(0, 0.32, 2.0)
	collector.deposit_pos = Vector3(0, 0, 4.0)
	collector.waypoints = [Vector3(0, 0, 0), Vector3(0, 0, 2.0)]
	collector.global_position = Vector3(0, 0.2, 0)
	collector.remains = []
	collector.reset()
	var picked_bot := false
	var froze_bot := false
	collector.bot_delivered.connect(func(_b) -> void: _bot_delivered = true)
	for _i in 420:
		await get_tree().physics_frame
		if collector.carried_bot == bot:
			picked_bot = true
			if bot.carried and bot.velocity == Vector3.ZERO:
				froze_bot = true
		if _bot_delivered:
			break
	_check(picked_bot, "the Collector picks up a chassis it finds")
	_check(froze_bot, "the carried chassis is frozen, not steered")
	_check(_bot_delivered and collector.carried_bot == null,
			"the Collector sets the chassis down at the drop point")
	_check(is_instance_valid(bot) and not bot.carried,
			"the chassis survives the ride (link is never cut)")
	_check(bot.global_position.distance_to(Vector3(0, 0.32, 2.0)) < 0.15,
			"the chassis lands on the Processor's drop mark")
	bot.queue_free()

	# --- Player awareness --------------------------------------------------
	# The Collector notices the walking player, watches them from long range,
	# shuffles in only once they are close, and throws a harmless stand-in
	# vomit at them before trying the grab. A visible player is looked at
	# whether they move or stand still.
	var test_floor := StaticBody3D.new()
	add_child(test_floor)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8, 0.2, 8)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -0.1, 2)
	test_floor.add_child(floor_shape)
	var target_body := Node3D.new()
	target_body.position = Vector3(0, 0.2, 3.0)
	add_child(target_body)
	var target_head := Node3D.new()
	target_head.name = "Head"
	target_head.position = Vector3(0, 1.6, 0)
	target_body.add_child(target_head)
	collector.player_body = target_body
	collector.player_target = null
	collector.waypoints = []
	collector.remains = []
	collector.deposit_pos = Vector3(100, 0, 100)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.reset()
	var saw_target := false
	var saw_look := false
	for _i in 360:
		await get_tree().physics_frame
		if collector.target == target_body and collector.pursuing:
			saw_target = true
		if collector._look.influence > 0.5:
			saw_look = true
		if collector.vomits > 0 and collector.grab_attempts > 0:
			break
	_check(saw_target, "the Collector fixates on a nearby player")
	_check(saw_look, "the Collector looks at a visible still player")
	_check(collector.vomits > 0, "the Collector vomits when the player is close")
	_check(collector.vomit_drops >= 12,
			"the vomit is a spray of many individual droplets")
	_check(collector.grab_attempts > 0,
			"the Collector attempts to pick the player up")

	target_body.position = Vector3(0, 0.2, 30.0)
	await _wait(4)
	_check(collector.target == null and not collector.pursuing,
			"the Collector gives up when the player gets too far away")
	_check(collector._look.influence == 0.0,
			"the Collector stops tracking an out-of-range player")
	collector.player_body = null
	target_body.queue_free()

	# The active chassis is the other player body: the Collector should chase
	# it and use the existing lift, not just stand over it.
	var chase_bot := DummyBot.new()
	add_child(chase_bot)
	chase_bot.global_position = Vector3(0, 0.2, 3.0)
	collector.player_body = null
	collector.player_target = chase_bot
	collector.bots = [chase_bot]
	collector.waypoints = [Vector3(0, 0, 0), Vector3(0, 0, 6)]
	collector.bot_drop_pos = Vector3(0, 0.32, 6.0)
	collector.deposit_pos = Vector3(100, 0, 100)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.reset()
	var picked_target := false
	for _i in 420:
		await get_tree().physics_frame
		if collector.carried_bot == chase_bot and chase_bot.carried:
			picked_target = true
			break
	_check(picked_target, "the Collector lifts the player's active chassis")
	collector.release_carried()
	collector.player_target = null
	chase_bot.queue_free()

	# --- Drone awareness ---------------------------------------------------
	# The head turns at long range whenever the drone is visible, moving or
	# not. The body only turns onto the drone during the active pickup
	# approach, and the feet only commit inside CHASE_RANGE.
	var drone := DummyBot.new()
	add_child(drone)
	collector.player_body = null
	collector.player_target = drone
	collector.bots = []
	collector.remains = []
	collector.deposit_pos = Vector3(100, 0, 100)
	collector.bot_drop_pos = Vector3(100, 0, 100)
	collector.global_position = Vector3(0, 0.2, 0)

	# Far away and idle: seen and looked at, but neither chased nor faced.
	collector.waypoints = []
	drone.global_position = Vector3(12, 0.2, 0)
	drone.velocity = Vector3.ZERO
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 999.0
	await _wait(20)
	_check(collector.target == drone and not collector.pursuing,
			"a far drone is noticed but not chased")
	_check(collector._look.influence > 0.9,
			"the head turns toward a still drone at 12 m")
	_check(absf(collector.rotation.y) < 0.1,
			"an idle body does not turn toward a far drone")

	# The head keeps tracking a moving drone, and does not forget it when it
	# stops.
	drone.velocity = Vector3(2.0, 0.0, 0.0)
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 999.0
	await _wait(20)
	_check(collector.target == drone and not collector.pursuing,
			"a moving far drone is noticed but not chased")
	_check(collector._look.influence > 0.9,
			"the head tracks a moving drone at 12 m")
	_check(absf(collector.rotation.y) < 0.1,
			"the body does not turn toward a moving far drone")
	drone.velocity = Vector3.ZERO
	await _wait(20)
	_check(collector._look.influence > 0.9,
			"the head keeps tracking a drone that just stopped")

	# A wall between them breaks the look; clearing it restores the look.
	var wall := StaticBody3D.new()
	add_child(wall)
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.6, 3.0, 2.0)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(6.0, 1.2, 0.0)
	wall.add_child(wall_shape)
	await _wait(20)
	_check(collector._look.influence == 0.0,
			"a wall between the Collector and the drone breaks the look")
	wall.queue_free()
	await _wait(10)
	_check(collector._look.influence > 0.9,
			"the look returns when line of sight is restored")

	# Far away while walking the authored route: head yes, body no.
	collector.waypoints = [Vector3(0, 0.2, -4)]
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 999.0
	await _wait(30)
	_check(collector._look.influence > 0.9,
			"the head stays on a visible drone while patrolling")
	_check(absf(collector.rotation.y) < 0.1,
			"a patrolling body faces its route, not a far drone")

	# Close, idle, standing at PURSUE_STOP: the head looks, the body holds.
	collector.waypoints = []
	drone.global_position = Vector3(0.6, 0.2, 0)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 999.0
	await _wait(20)
	_check(collector.target == drone and collector.pursuing,
			"a drone inside CHASE_RANGE is fixated on")
	_check(collector._look.influence > 0.9,
			"the head looks at an idle drone at close range")
	_check(absf(collector.rotation.y) < 0.1,
			"a body standing at PURSUE_STOP does not turn onto the drone")

	# The spray reaches farther than the chase: at 6 m it squares up and
	# spits without leaving its ground.
	drone.global_position = Vector3(6.0, 0.2, 0)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.waypoints = [Vector3(0, 0.2, -4)]
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 0.0
	var vomits_before: int = collector.vomits
	await _wait(40)
	_check(not collector.pursuing,
			"the Collector does not chase a player outside CHASE_RANGE")
	_check(collector.vomits > vomits_before,
			"the Collector spits at a player outside CHASE_RANGE")
	_check(absf(angle_difference(collector.rotation.y, -PI * 0.5)) < 0.3,
			"the mid-range spit turns the body onto the player")

	# Active approach: the body may now turn onto the drone.
	drone.global_position = Vector3(3.0, 0.2, 0)
	collector.global_position = Vector3(0, 0.2, 0)
	collector.reset()
	collector.rotation.y = 0.0
	collector._vomit_cd = 999.0
	await _wait(60)
	_check(collector.pursuing, "the Collector actively pursues a drone in range")
	_check(absf(angle_difference(collector.rotation.y, -PI * 0.5)) < 0.3,
			"the body turns toward the drone while moving to pick it up")

	# --- Ground vomit ------------------------------------------------------
	# A separate, harmless beat from the attack spray: walking its route with
	# no player around, the Collector stops, folds slightly, spits at the deck
	# ahead and walks on. Clear both player bodies so this cannot read as an
	# attack, and keep the route on the suite's 8x8 test floor.
	collector.player_body = null
	collector.player_target = null
	collector.bots = []
	collector.remains = []
	collector.deposit_pos = Vector3(100, 0, 100)
	collector.bot_drop_pos = Vector3(100, 0, 100)
	collector.waypoints = [Vector3(-2.5, 0, 2), Vector3(2.5, 0, 2)]
	collector.global_position = Vector3(0, 0.2, 2)
	collector.reset()
	# Let the body settle onto the route's heading before forcing the beat, so
	# the measured "forward" is the direction it is actually walking.
	await _wait(45)
	var ground_before: int = collector.ground_vomits
	var children_before: int = collector.get_child_count()
	var statics_before: int = _count_type(collector, "StaticBody3D")
	var shapes_before: int = _count_type(collector, "CollisionShape3D")
	var vomit_before: int = _count_vomit(self)
	var rest_head: Vector3 = (collector._skeleton.global_transform \
			* collector._skeleton.get_bone_global_pose(collector._head_bone)).origin
	collector.force_ground_vomit()
	var saw_ground := false
	var steady := true
	var peak_bend := 0.0
	var head_shift := 0.0
	var head_drop := 0.0
	var wp_during := -1
	for _i in 120:
		await get_tree().physics_frame
		if collector.ground_vomits > ground_before:
			saw_ground = true
		if not saw_ground:
			continue
		if wp_during < 0:
			wp_during = collector._wp
		if collector._ground_vomit_t <= 0.0:
			break
		if Vector2(collector.velocity.x, collector.velocity.z).length() >= 0.05:
			steady = false
		peak_bend = maxf(peak_bend, collector.ground_bend)
		var head: Vector3 = (collector._skeleton.global_transform \
				* collector._skeleton.get_bone_global_pose(collector._head_bone)).origin
		var forward: Vector3 = -collector.global_transform.basis.z
		head_shift = maxf(head_shift, (head - rest_head).dot(forward))
		head_drop = maxf(head_drop, rest_head.y - head.y)
	_check(saw_ground, "the Collector stops for a ground vomit on its route")
	_check(steady, "the ground vomit halts the body")
	_check(collector.ground_vomit_drops >= 10,
			"the ground vomit sprays droplets at the deck ahead")
	_check(peak_bend > 0.5, "the Collector folds into the ground vomit")
	_check(head_shift > 0.02 or head_drop > 0.02,
			"the bend shifts the head toward the deck ahead")

	var walking_again := false
	for _i in 240:
		await get_tree().physics_frame
		if collector._ground_vomit_t <= 0.0 and collector.ground_bend < 0.1 \
				and Vector2(collector.velocity.x, collector.velocity.z).length() > 0.1:
			walking_again = true
			break
	_check(walking_again and collector.ground_bend < 0.1,
			"the Collector straightens and walks on after the ground vomit")
	_check(wp_during >= 0 and collector._wp == wp_during,
			"the ground vomit does not advance the route")
	var ground_after_beat: int = collector.ground_vomits
	var repeated := false
	for _i in 30:
		await get_tree().physics_frame
		if collector.ground_vomits > ground_after_beat:
			repeated = true
	_check(collector.ground_vomits == ground_before + 1,
			"one forced ground vomit produces exactly one beat")
	_check(not repeated, "the ground vomit does not repeat without a new cooldown")
	_check(collector.get_child_count() == children_before
			and _count_type(collector, "StaticBody3D") == statics_before
			and _count_type(collector, "CollisionShape3D") == shapes_before,
			"the ground vomit leaves no permanent body on the Collector")
	await _wait(180)
	_check(_count_vomit(self) == vomit_before,
			"the ground vomit droplets free themselves")

	# A visible player in attack range still gets the attack spray first: the
	# ground cooldown is zero, but the beat must not pre-empt the spit.
	var spray_body := Node3D.new()
	spray_body.position = Vector3(6.0, 0.2, 2.0)
	add_child(spray_body)
	var spray_head := Node3D.new()
	spray_head.name = "Head"
	spray_head.position = Vector3(0, 1.6, 0)
	spray_body.add_child(spray_head)
	collector.player_body = spray_body
	collector.player_target = null
	collector.global_position = Vector3(0, 0.2, 2)
	collector.waypoints = [Vector3(-2.5, 0, 2), Vector3(2.5, 0, 2)]
	collector.reset()
	collector._ground_vomit_cd = 0.0
	var vomits_before_spray: int = collector.vomits
	var ground_during_spray: int = collector.ground_vomits
	var sprayed := false
	var ground_pre_empted := false
	for _i in 60:
		await get_tree().physics_frame
		if collector._vomit_t > 0.0:
			sprayed = true
		if collector.ground_vomits > ground_during_spray:
			ground_pre_empted = true
		if sprayed and collector.vomits > vomits_before_spray:
			break
	_check(collector.vomits > vomits_before_spray,
			"the attack spray still fires at a nearby player")
	_check(sprayed, "the attack spray keeps its rooted spray window")
	_check(not ground_pre_empted and collector.ground_vomits == ground_during_spray,
			"the ground vomit yields to a player in spray range")
	collector.player_body = null
	spray_body.queue_free()

	collector.player_target = null
	drone.queue_free()
	test_floor.queue_free()

	print("COLLECTOR AI %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
