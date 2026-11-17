extends Node3D
## Crawler set-piece probe. The survivor in the Cold Hold side hall is a
## one-shot, collision-free actor: it crawls toward the lamp, stops short,
## talks, and is yanked away, leaving only smears. It must never kill, be
## saved, or soft-lock the drone.
##
## Run: godot --headless --path . res://tests/crawler_setpiece.tscn

const CRAWLER_SCENE := preload("res://scenes/actors/crawler.tscn")

var _failed := false
var _said: Array = []
var _finished := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_failed = true


func _run() -> void:
	await get_tree().physics_frame
	_check(NoiseBus != null, "the noise bus is available to the set piece")

	var crawler = CRAWLER_SCENE.instantiate()
	add_child(crawler)
	crawler.says.connect(func(text: String) -> void: _said.append(text))
	crawler.finished.connect(func() -> void: _finished += 1)

	var drone := Node3D.new()
	add_child(drone)
	drone.global_position = Vector3(21.0, 0.3, -56.0)
	var grab_mark := Vector3(21.0, 0.2, -62.0)
	var entrance := Vector3(21.0, 0.2, -47.0)

	_check(crawler is Node3D and not (crawler is PhysicsBody3D),
			"the crawler is not a physics body")
	_check(crawler.get_node_or_null("Rig/LegL") == null
			and crawler.get_node_or_null("Rig/LegR") == null,
			"the crawler has no legs")
	_check(crawler.radar_blips, "the crawler reads on radar as a drag source")

	var noise_before: int = NoiseBus.count
	crawler.start(grab_mark, entrance)
	crawler.drone = drone
	await get_tree().physics_frame
	_check(crawler.active and crawler._phase == 1,
			"the crawler starts crawling from the authored mark")
	_check(crawler.global_position.distance_to(grab_mark) < 0.01,
			"the authored grab mark is the crawl origin")
	_check(_said.size() >= 1, "the crawler speaks as it starts")

	var p0: Vector3 = crawler.global_position
	var d0: float = crawler.global_position.distance_to(drone.global_position)
	for _i in 120:
		await get_tree().physics_frame
	var p1: Vector3 = crawler.global_position
	var d1: float = crawler.global_position.distance_to(drone.global_position)
	var speed: float = p0.distance_to(p1) / 2.0
	_check(d1 < d0, "the crawler closes on the drone")
	_check(speed >= 0.45 and speed <= 1.0,
			"the crawl is slow and dragging (%.2f m/s)" % speed)
	_check(NoiseBus.count > noise_before,
			"the drag posts noise for radar and stills (%d events)"
			% (NoiseBus.count - noise_before))

	var close_frames := 0
	while crawler._phase == 1 and close_frames < 900:
		await get_tree().physics_frame
		close_frames += 1
	_check(crawler._phase == 2, "the crawler reaches its hold distance")
	_check(crawler.global_position.distance_to(drone.global_position)
			>= crawler.HOLD_DIST - 0.05,
			"the crawler never touches the drone (%.2f m)"
			% crawler.global_position.distance_to(drone.global_position))
	_check(_said.size() >= 2, "the crawler talks at the hold beat")

	var children_before := get_child_count()
	var yank_frames := 0
	while not crawler.done and yank_frames < 500:
		await get_tree().physics_frame
		yank_frames += 1
	_check(crawler.done and not crawler.active, "the yank ends the set piece")
	_check(_finished == 1, "the set piece reports exactly one finish")
	_check(not crawler._rig.visible, "the body is gone after the yank")
	_check(get_child_count() >= children_before + 6,
			"the smear and handprints remain on the deck")
	var still_there := false
	for child in get_children():
		if child is CSGBox3D and not child.use_collision:
			still_there = true
	_check(still_there, "the remains are visual-only and cannot block a lane")

	crawler.start(grab_mark, entrance)
	await get_tree().physics_frame
	_check(not crawler.active and crawler.done,
			"the set piece cannot be replayed in the same session")

	# Abandoning the hallway resolves the beat at the authored mark.
	var c2 = CRAWLER_SCENE.instantiate()
	add_child(c2)
	c2.drone = drone
	c2.start(grab_mark + Vector3(0, 0, 4), entrance)
	await get_tree().physics_frame
	_check(c2.active, "a second probe crawler starts")
	c2.abandon()
	var abandon_frames := 0
	while not c2.done and abandon_frames < 300:
		await get_tree().physics_frame
		abandon_frames += 1
	_check(c2.done and c2.global_position.distance_to(c2.grab_mark) < 0.05,
			"abandoning the hall yanks it at the authored mark")

	print("CRAWLER SETPIECE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
