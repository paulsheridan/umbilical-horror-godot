extends Node3D
## Focused probe for the Processor: the pinned body, motion-only sight, the
## telegraph/reach/catch escape window, feeding from the pile, and release
## after a fleet loss. Hall geometry is not asserted here.
##
## Run: godot --headless --path . res://tests/processor_ai.tscn

const SHIP_SCENE := preload("res://scenes/level/ship.tscn")
const PROCESSOR_SCENE := preload("res://scenes/actors/processor.tscn")

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
	ship = SHIP_SCENE.instantiate()
	add_child(ship)
	await _wait(2)

	# --- Layout data -------------------------------------------------------
	_check(ship.processor_pile != null, "the Processor's feeding pile exists")
	_check(ship.processor_pile.global_position.distance_to(ship.PROCESSOR_PILE) < 0.1,
			"the pile sits on the authored feed constant")

	# --- Body --------------------------------------------------------------
	processor = PROCESSOR_SCENE.instantiate()
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
	# Stage relative to the pinned body so moving its marker moves the probe.
	var fwd: Vector3 = -processor.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side: Vector3 = processor.global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	var front_pos: Vector3 = processor.global_position + fwd * 1.9 \
			+ Vector3(0.0, 0.2, 0.0)

	var still := DummyBot.new()
	add_child(still)
	still.global_position = front_pos
	still.velocity = Vector3.ZERO
	processor.drone = still
	await _wait(2)
	_check(not processor._can_see_drone(),
			"a still chassis is invisible to the Processor")

	# A moving chassis in the cone is seen; the same motion behind it is not.
	still.velocity = Vector3(0.8, 0.0, 0.0)
	_check(processor._can_see_drone(),
			"a moving chassis in the cone is seen")
	still.global_position = processor.global_position + side * 2.9 \
			+ Vector3(0.0, 0.2, 0.0)
	_check(not processor._can_see_drone(),
			"motion outside the frontal cone is not seen")
	still.global_position = front_pos

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
	bot.global_position = front_pos
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
	bot.global_position = processor.global_position + fwd * 4.7 \
			+ Vector3(0.0, 0.2, 0.0)
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
