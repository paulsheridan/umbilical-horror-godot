extends Node3D
## Focused probe for the Processor: the new east hall/chamber geometry, the
## pinned body, motion-only sight, the telegraph/reach/catch escape window,
## feeding from the pile, and release after a fleet loss.
##
## Run: godot --headless --path . res://tests/processor_ai.tscn

const BEYOND := preload("res://src/ship/beyond.gd")
const PROCESSOR := preload("res://src/host/processor.gd")

class DummyBot extends CharacterBody3D:
	var carried := false
	var bot_index := 0


var ship: Node3D
var processor: CharacterBody3D
var _failed := false
var _caught := 0


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
	_check(ship.processor_pile != null, "the Processor's feeding pile exists")
	_check(ship.processor_pile.global_position.distance_to(ship.PROCESSOR_PILE) < 0.1,
			"the pile sits on the authored feed constant")
	var hall_len: float = ship.PROC_HALL_X1 - ship.PROC_HALL_X0
	_check(hall_len >= 6.0, "the Processor hall is long (%.1f m)" % hall_len)
	_check(ship.PROCESSOR_PILE.distance_to(ship.PROCESSOR_POS) < 3.0,
			"the pile is inside arm's reach of the pinned body")
	_check(ship.PROCESSOR_DROP.distance_to(ship.PROCESSOR_POS) < 4.0,
			"the Collector's drop point is at the mouth's edge")

	# The hall is enclosed except at both ends and the chamber mouth. A drone-
	# height ray straight down the hall reaches the pile without a wall stop.
	var space := get_world_3d().direct_space_state
	var down_hall := PhysicsRayQueryParameters3D.create(
			Vector3(21.6, 0.55, -11.7), Vector3(28.7, 0.55, -11.7), 1)
	_check(space.intersect_ray(down_hall).is_empty(),
			"the whole Processor hall is open at drone height")
	var hall_side := PhysicsRayQueryParameters3D.create(
			Vector3(24.5, 1.45, -13.6), Vector3(24.5, 1.45, -9.8), 1)
	_check(not space.intersect_ray(hall_side).is_empty(),
			"the hall has solid north/south walls")

	# --- Body --------------------------------------------------------------
	processor = CharacterBody3D.new()
	processor.set_script(PROCESSOR)
	add_child(processor)
	processor.global_position = Vector3(ship.PROCESSOR_POS.x, 0.0,
			ship.PROCESSOR_POS.z)
	processor.rotation.y = PI * 0.5
	processor.pile = ship.processor_pile
	processor.reset()
	processor.drone_caught.connect(func() -> void: _caught += 1)
	await _wait(2)

	_check(processor.is_in_group("hosts"), "the Processor is registered as a host")
	_check(not processor.radar_blips, "the Processor makes no radar blips")
	_check(not processor.has_method("_on_noise"),
			"the Processor is deaf to noise")
	_check(processor.pinned, "the Processor is flagged pinned")
	_check(processor._hands.size() == 2, "it has two gaunt hands")
	_check(processor._jaw != null, "it has a hinged jaw")

	var pinned_pos: Vector3 = processor.global_position
	await _wait(60)
	_check(processor.global_position.distance_to(pinned_pos) < 0.001,
			"the pinned body never walks")

	# --- Motion-only sight -------------------------------------------------
	var still := DummyBot.new()
	add_child(still)
	still.global_position = Vector3(30.2, 0.2, -11.7)
	still.velocity = Vector3.ZERO
	processor.drone = still
	await _wait(2)
	_check(not processor._can_see_drone(),
			"a still chassis is invisible to the Processor")

	# A moving chassis in the cone is seen; the same motion behind it is not.
	still.velocity = Vector3(0.8, 0.0, 0.0)
	_check(processor._can_see_drone(),
			"a moving chassis in the cone is seen")
	still.global_position = Vector3(32.1, 0.2, -14.6)
	_check(not processor._can_see_drone(),
			"motion outside the frontal cone is not seen")
	still.global_position = Vector3(30.2, 0.2, -11.7)

	# A carried chassis is cargo, not food.
	still.carried = true
	_check(not processor._can_see_drone(),
			"a Collector-carried chassis is ignored")
	still.carried = false
	still.queue_free()
	processor.drone = null
	await _wait(2)

	# --- Telegraph, reach, catch ------------------------------------------
	var bot := DummyBot.new()
	add_child(bot)
	bot.global_position = Vector3(30.2, 0.2, -11.7)
	processor.drone = bot
	processor.reset()
	_caught = 0
	var saw_telegraph := false
	for _i in 300:
		bot.velocity = Vector3(0.7, 0.0, 0.0)
		await get_tree().physics_frame
		if processor.state == processor.State.TELEGRAPH:
			saw_telegraph = true
		if processor.state == processor.State.DEVOUR:
			break
	_check(saw_telegraph, "the reach is telegraphed before it happens")
	_check(processor.state == processor.State.DEVOUR and _caught == 1,
			"a chassis held in reach is caught and devoured")
	_check(processor.catches == 1, "the catch is counted")

	processor.release_catch()
	await _wait(4)
	_check(processor._devour_bot == null,
			"release_catch lets go after the fleet absorbs the loss")

	# --- Escape window -----------------------------------------------------
	# A confirmed catch is only possible inside MAX_REACH. A bot that drives
	# past the hand's reach survives the same telegraph.
	bot.global_position = Vector3(27.4, 0.2, -11.7)
	processor.drone = bot
	processor.reset()
	_caught = 0
	for _i in 300:
		bot.velocity = Vector3(0.7, 0.0, 0.0)
		await get_tree().physics_frame
	_check(_caught == 0 and processor.state != processor.State.DEVOUR,
			"a chassis beyond the hand's reach escapes the grasp")
	bot.queue_free()
	processor.drone = null
	await _wait(2)

	# --- Feeding -----------------------------------------------------------
	for c in ship.processor_pile.get_children():
		c.queue_free()
	await _wait(2)
	var part := CSGBox3D.new()
	part.size = Vector3(0.24, 0.08, 0.10)
	part.position = Vector3(0.1, 0.12, 0.0)
	ship.processor_pile.add_child(part)
	var before: int = processor.consumed
	processor.reset()
	var ate := false
	for _i in 600:
		await get_tree().physics_frame
		if processor.consumed > before:
			ate = true
			break
	_check(ate, "the Processor picks a part off the pile and consumes it")
	await _wait(4)
	_check(not is_instance_valid(part), "the eaten part is removed from the pile")
	_check(processor.consumed > 0, "consumption is counted")

	print("PROCESSOR AI %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
