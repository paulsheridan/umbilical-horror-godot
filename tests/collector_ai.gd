extends Node3D
## Focused probe for the berth wing and the Collector: geometry gates, loud
## doors, bed hides, remains, pickup/deposit, and the stalker's choke detour.
##
## Run: godot --headless --path . res://tests/collector_ai.tscn

const BEYOND := preload("res://src/ship/beyond.gd")
const COLLECTOR := preload("res://src/host/collector.gd")
const STALKER := preload("res://src/host/stalker.gd")

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


func _run() -> void:
	ship = BEYOND.new()
	add_child(ship)
	ship.build()
	await _wait(2)

	# --- Layout ------------------------------------------------------------
	var bunks := 0
	for spot in ship.hide_spots:
		var c: Vector3 = spot["center"]
		if c.z > -10.5 and c.x > 7.0:
			bunks += 1
	_check(ship.hide_spots.size() >= 6, "tables and bunks are all hide spots")
	_check(bunks == 3, "three lofted bunks are hide spots (%d)" % bunks)
	_check(ship.loud_doors.size() == 4, "four loud cabin doors")
	_check(ship.remains.size() == 12, "twelve scattered remains")
	_check(ship.collector_pile != null, "the Collector's deposit node exists")
	_check(ship.collector_pile.global_position.distance_to(ship.COLLECTOR_DEPOSIT) < 0.1,
			"deposit node sits on the movable deposit constant")
	_check(ship.chokes.size() == 2, "the crawl and the locker link are chokes")

	# A drone-height ray crosses the low crawl; a body-height ray is stopped
	# by its header. Same proof for the fallen-locker link.
	var space := get_world_3d().direct_space_state
	var low := PhysicsRayQueryParameters3D.create(
			Vector3(13.2, 0.55, -17.2), Vector3(13.2, 0.55, -12.0), 1)
	_check(space.intersect_ray(low).is_empty(), "drone-height crawl is clear")
	var high := PhysicsRayQueryParameters3D.create(
			Vector3(13.2, 1.45, -17.2), Vector3(13.2, 1.45, -12.0), 1)
	_check(not space.intersect_ray(high).is_empty(), "body-height crawl is blocked")
	var locker_low := PhysicsRayQueryParameters3D.create(
			Vector3(8.6, 0.55, -17.2), Vector3(8.6, 0.55, -12.0), 1)
	_check(space.intersect_ray(locker_low).is_empty(), "drone passes under the fallen locker")
	var locker_high := PhysicsRayQueryParameters3D.create(
			Vector3(8.6, 1.45, -17.2), Vector3(8.6, 1.45, -12.0), 1)
	_check(not space.intersect_ray(locker_high).is_empty(), "the locker blocks a body")

	# --- Loud doors --------------------------------------------------------
	NoiseBus.clear()
	var door = ship.loud_doors[0]
	var start_x: float = door["node"].position.x
	ship.service_doors(Vector3(8.9, 0.32, -11.5), 0.016)
	_check(door["opening"], "a nearby drone triggers the cabin door")
	_check(NoiseBus.count > 0, "opening a cabin door posts noise")
	for _i in 90:
		ship.service_doors(Vector3(8.9, 0.32, -11.5), 1.0 / 60.0)
	_check(door["node"].position.x > start_x + 0.9, "the door slides open")
	_check(door["settled"], "the door settles open")

	# --- Collector ---------------------------------------------------------
	collector = CharacterBody3D.new()
	collector.set_script(COLLECTOR)
	add_child(collector)
	collector.global_position = Vector3(0, 0.2, 0)
	await _wait(1)
	_check(collector._rig != null and collector._sack != null,
			"the Collector has a modelled body and a drag sack")
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

	# --- Stalker choke routing --------------------------------------------
	var stalker := CharacterBody3D.new()
	stalker.set_script(STALKER)
	add_child(stalker)
	stalker.chokes = ship.chokes
	stalker.set_physics_process(false)

	stalker.global_position = Vector3(13.2, 0.2, -16.8)
	stalker._detour.clear()
	var to_hall: Vector3 = stalker._nav_target(Vector3(13.2, 0.2, -11.5))
	_check(to_hall.distance_to(Vector3(17.6, 0.0, -16.8)) < 0.2,
			"in the ring, the stalker routes to the east link")
	stalker.global_position = Vector3(13.2, 0.2, -11.5)
	stalker._detour.clear()
	var to_ring: Vector3 = stalker._nav_target(Vector3(13.2, 0.2, -16.8))
	_check(to_ring.distance_to(Vector3(17.6, 0.0, -11.8)) < 0.2,
			"in the hall, it routes back through the east link")
	stalker.global_position = Vector3(13.2, 0.2, -11.5)
	stalker._detour.clear()
	var same_side: Vector3 = stalker._nav_target(Vector3(15.0, 0.2, -11.2))
	_check(same_side.distance_to(Vector3(15.0, 0.2, -11.2)) < 0.01,
			"no detour when both bodies are on the same side")

	# Physical proof: an investigate target across the crawl makes it walk the
	# east link and arrive in the hall rather than wedge at the low header.
	stalker.global_position = Vector3(13.2, 0.2, -16.8)
	stalker.set_physics_process(true)
	stalker.state = stalker.State.INVESTIGATE
	stalker._investigate_target = Vector3(13.2, 0.2, -11.5)
	stalker._investigate_t = 0.0
	stalker._detour.clear()
	for _i in 900:
		await get_tree().physics_frame
		if stalker.state == stalker.State.SEARCH:
			break
	_check(stalker.global_position.z > -13.0,
			"the stalker physically walks around the crawl (z %.1f)" % stalker.global_position.z)
	_check(stalker.global_position.distance_to(Vector3(13.2, 0.2, -11.5)) < 1.2,
			"the stalker reaches the hall side of the choke")

	print("COLLECTOR AI %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
