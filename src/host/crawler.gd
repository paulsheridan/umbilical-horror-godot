extends Node3D
## The Crawler — a one-shot set piece in the Cold Hold's side hallway.
##
## A human survivor with no legs drags itself toward the drone's lamp, talking
## in a filtered, half-broken voice. It is not a monster and cannot kill, be
## saved, or soft-lock anything: it is a fixed piece of horror with an authored
## start, hold distance, and end.
##
## Contract:
##   - triggered once at the hallway entrance, deferred while a host is close;
##   - crawls at 0.6-0.9 m/s, never closer than ~2.6 m;
##   - a long alien arm yanks it back at that distance or after ~15 s;
##   - the scream cuts off, the body disappears, and smears/handprints remain;
##   - if the drone leaves, it resolves at the authored grab mark;
##   - it posts drag noise, so radar and stills both carry it.

signal says(text: String)
signal finished

const Mats := preload("res://src/mats.gd")

const SPEED_MIN := 0.60
const SPEED_MAX := 0.90
const HOLD_DIST := 2.6          # never crawls inside this
const YANK_TIME := 15.0         # or after this long, whichever comes first
const HOLD_VOICE_TIME := 2.6
const YANK_ANIM := 1.25
const YANK_DRAG := 16.0
const SCRAPE_INTERVAL := 0.55

## The one-shot beat speaks a single line, so this holds exactly that line.
const LINES := [
	"It's in the walls.",
]

var drone = null
var entrance := Vector3.ZERO
var grab_mark := Vector3.ZERO
var active := false
var done := false
## Radar reads it as a noise source, not a body mass.
var radar_blips := true

var _phase := 0                  # 0 dormant, 1 crawl, 2 hold/talk, 3 yank
var _t := 0.0
var _hold_t := 0.0
var _yank_t := 0.0
var _scrape_t := 0.0
## Direction of the final drag: toward the hallway's far opening, not simply
## away from the drone. Set from the authored entrance/grab marks at start().
var _yank_dir_world := Vector3(0.0, 0.0, -1.0)
var _yank_dir_local := Vector3(0.0, 0.0, 1.0)
var _rng := RandomNumberGenerator.new()

var _rig: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _alien_arm: Node3D
var _eyes: Array = []


func _ready() -> void:
	_rng.randomize()
	_rig = $Rig
	_torso = $Rig/Torso
	_head = $Rig/Head
	_arm_l = $Rig/ArmL
	_arm_r = $Rig/ArmR
	_alien_arm = $Rig/AlienArm
	_eyes = [$Rig/Head/EyeL, $Rig/Head/EyeR]
	if _alien_arm != null:
		_alien_arm.visible = false


## Begin the crawl from the dark end of the hallway toward the drone.
func start(from_pos: Vector3, face_pos: Vector3) -> void:
	if active or done:
		return
	global_position = from_pos
	entrance = face_pos
	grab_mark = from_pos
	active = true
	_phase = 1
	_t = 0.0
	_hold_t = 0.0
	_yank_t = 0.0
	_scrape_t = 0.0
	visible = true
	if _rig != null:
		_rig.visible = true
	if _alien_arm != null:
		_alien_arm.visible = false
	_face(face_pos)
	var into := from_pos - face_pos
	into.y = 0.0
	if into.length() < 0.1:
		into = Vector3(0.0, 0.0, -1.0)
	_yank_dir_world = into.normalized()
	_yank_dir_local = _yank_dir_world.rotated(Vector3.UP, -rotation.y)
	_yank_dir_local.y = 0.0
	if _yank_dir_local.length() < 0.01:
		_yank_dir_local = Vector3(0.0, 0.0, 1.0)
	else:
		_yank_dir_local = _yank_dir_local.normalized()
	_say(LINES[0])
	Sfx.play("crawler_voice", global_position, -2.0, 0.92)


## Resolve at the authored mark when the drone abandons the hallway.
func abandon() -> void:
	if not active or done:
		return
	if _phase < 3:
		global_position = grab_mark
		_yank()


func force_yank() -> void:
	if active and not done and _phase < 3:
		_yank()


func _process(delta: float) -> void:
	if GameState.paused:
		return
	if not active or done:
		return
	_t += delta
	_scrape_t -= delta
	if _scrape_t <= 0.0:
		_scrape_t = SCRAPE_INTERVAL
		Sfx.play("crawler_drag", global_position, -8.0, _rng.randf_range(0.85, 1.1))
		# Environment noise, untagged: the scanner paints it and hosts can hear.
		NoiseBus.emit_noise(global_position, 0.46)

	match _phase:
		1:
			_crawl(delta)
		2:
			_hold(delta)
		3:
			_yank_tick(delta)
	_animate(delta)


func _crawl(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		abandon()
		return
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d <= HOLD_DIST:
		_phase = 2
		_hold_t = 0.0
		_say(LINES[0])
		Sfx.play("crawler_voice", global_position, -1.0, 0.86)
		return
	if _t >= YANK_TIME:
		force_yank()
		return
	# Slow, uneven drag: the body is pulling itself with its arms.
	var speed := clampf(0.74 + 0.12 * sin(_t * 1.7), SPEED_MIN, SPEED_MAX)
	var dir := to / d
	global_position += dir * speed * delta
	_face(drone.global_position)
	# It closes the last little bit only on the authored beat, never touching.
	if global_position.distance_to(drone.global_position) <= HOLD_DIST:
		_phase = 2
		_hold_t = 0.0
		_say(LINES[0])
		Sfx.play("crawler_voice", global_position, -1.0, 0.86)


func _hold(delta: float) -> void:
	if drone == null or not is_instance_valid(drone):
		abandon()
		return
	_hold_t += delta
	_face(drone.global_position)
	if _hold_t >= HOLD_VOICE_TIME:
		force_yank()


func _yank() -> void:
	if _phase >= 3 or done:
		return
	_phase = 3
	_yank_t = 0.0
	if _alien_arm != null:
		_alien_arm.visible = true
	# The voice cuts off into the snap.
	Sfx.play("crawler_scream", global_position, 0.0, 1.02)
	_say("No.")
	_spawn_remains()


func _yank_tick(delta: float) -> void:
	_yank_t += delta
	if _alien_arm != null:
		_alien_arm.visible = true
	if _rig != null:
		# Dragged toward the far opening, fast and accelerating, until it
		# vanishes into the next room.
		var p := clampf(_yank_t / YANK_ANIM, 0.0, 1.0)
		_rig.position = _yank_dir_local * (YANK_DRAG * p * p)
		_rig.rotation.x = minf(0.55, _yank_t * 1.8)
	if _yank_t >= YANK_ANIM:
		_finish()


func _finish() -> void:
	if done:
		return
	done = true
	active = false
	_phase = 0
	Sfx.play("wet_snap", global_position, -1.0, 0.78)
	if _rig != null:
		_rig.visible = false
	finished.emit()


func _say(text: String) -> void:
	says.emit(text)


func _face(target: Vector3) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return
	rotation.y = atan2(-flat.x, -flat.z)


## A long drag trail and handprints: the only things left when it is gone.
## The trail follows the yank direction (local +Z), so it reads as a body
## hauled back down the hall toward the far opening.
func _spawn_remains() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var back := _yank_dir_world
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3(0.0, 0.0, -1.0)
	back = back.normalized()
	var yaw := atan2(back.x, back.z)
	var steps := int(YANK_DRAG / 0.9)
	for i in steps:
		var d := 0.3 + float(i) * (YANK_DRAG - 0.6) / float(maxi(steps - 1, 1))
		var smear := CSGBox3D.new()
		smear.size = Vector3(_rng.randf_range(0.30, 0.50), 0.012,
				_rng.randf_range(0.65, 1.25))
		smear.position = global_position + back * d + Vector3(
				_rng.randf_range(-0.16, 0.16), -0.14,
				_rng.randf_range(-0.16, 0.16))
		smear.rotation.y = yaw + _rng.randf_range(-0.22, 0.22)
		smear.material = Mats.flesh()
		smear.use_collision = false
		parent.add_child(smear)
	for d in [0.2, 2.2]:
		for side in [-1.0, 1.0]:
			var print := CSGBox3D.new()
			print.size = Vector3(0.14, 0.010, 0.22)
			print.position = global_position + back * float(d) \
					+ Vector3(side * 0.32, -0.14, 0.0)
			print.rotation.y = yaw + 0.25 * side
			print.material = Mats.cable()
			print.use_collision = false
			parent.add_child(print)


func _animate(delta: float) -> void:
	var gait := _t * 5.0
	if _torso != null:
		_torso.position.y = 0.30 + absf(sin(gait * 0.5)) * 0.018
		_torso.rotation.z = sin(gait * 0.45) * 0.06
	if _head != null:
		_head.rotation.x = 0.45 + sin(gait * 0.35) * 0.10
		_head.rotation.z = sin(gait * 0.28) * 0.08
	if _arm_l != null:
		_arm_l.rotation.x = -0.25 + sin(gait) * 0.55
	if _arm_r != null:
		_arm_r.rotation.x = -0.25 - sin(gait) * 0.55
	if _alien_arm != null and _alien_arm.visible and _phase == 3:
		_alien_arm.position.z = lerpf(-2.6, -0.2,
				clampf(_yank_t / YANK_ANIM, 0.0, 1.0))
