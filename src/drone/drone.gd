extends CharacterBody3D
## The remote drone body (M1: blind-era crawler — no camera, motor, tether).
## Controlled only while GameState.sortie == PILOTING. Heavy, slow, loud:
## scrapes post to NoiseBus, and the tether constrains position softly.
## Battery drains in real time; at zero the winch hauls it home blind.
## Each chassis keeps its own cargo, heading and charge; `controlled` is true
## only for the bot the player currently holds the link to.

signal feed_message(text: String)
signal battery_dead

const MAX_TETHER := 36.0
const WALK_SPEED := 1.9
const HURRY_SPEED := 2.6
const ACCEL := 3.0
const TURN_RATE := 1.7
const GRAVITY := 12.0
const BATTERY_RATE := 0.22   # %/s -> ~7.5 min sortie
const MOTOR_NOISE_INTERVAL := 0.9   # drive = heard; stop = silence

# Fluent refs (set up in _ready; no class-cache globals relied on).
const Mats := preload("res://src/mats.gd")

var controlled := false
## First drone iteration: live drone view is OFF (main sets this false). The
## camera node still exists because the still-photo SubViewport copies its
## transform for each exposure; it just never becomes the main viewport camera.
## Set true to restore the live feed.
var live_view := false
var battery := 100.0
var anchor_pos := Vector3.ZERO
var dock_pos := Vector3.ZERO
var cam: Camera3D
var motor: AudioStreamPlayer = null
## Per-chassis state. The fleet shares one active link but each bot keeps its
## own position, heading, charge and cargo while the player is elsewhere.
var cargo := ""
var bot_index := 0
## True while the Collector is carrying this chassis. The link, camera and
## charge stay live; only self-movement is suspended. The Collector places the
## body each frame, and the player can watch the whole ride.
var carried := false
var _led: CSGBox3D = null

var _scrape_cd := 0.0
var _motor_noise_t := 0.0


func _exit_tree() -> void:
	# Release the motor loop cleanly on teardown/shutdown (Sfx._exit_tree
	# handles the global hum, the drone's loop lives here).
	set_controlled(false)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.72, 0.5, 0.95)
	col.shape = box
	col.position = Vector3(0, 0.3, 0)
	add_child(col)

	# --- Chassis (crawler graybox) ------------------------------------------
	var body := CSGBox3D.new()
	body.size = Vector3(0.72, 0.3, 0.95)
	body.position = Vector3(0, 0.32, 0)
	body.material = Mats.machine()
	add_child(body)
	for side in [-1.0, 1.0]:
		var track := CSGCylinder3D.new()
		track.radius = 0.16
		track.height = 0.94
		track.position = Vector3(side * 0.33, 0.16, 0)
		track.rotation = Vector3(0, 0, PI * 0.5)
		track.material = Mats.cable()
		add_child(track)
	# The camera barrel: the still optic is always aboard, and the salvaged
	# video module wakes the live feed that looks through it.
	var barrel := CSGCylinder3D.new()
	barrel.radius = 0.09
	barrel.height = 0.3
	barrel.position = Vector3(0, 0.5, -0.45)
	barrel.rotation = Vector3(PI * 0.5, 0, 0)
	barrel.material = Mats.screen_off()
	add_child(barrel)
	var led := CSGBox3D.new()
	led.size = Vector3(0.09, 0.03, 0.09)
	led.position = Vector3(0, 0.49, 0.45)
	led.material = Mats.amber()
	add_child(led)
	_led = led

	# --- Head: status-lamp "vision" only ------------------------------------
	var head := Node3D.new()
	head.position = Vector3(0, 0.92, 0.05)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.04
	head.add_child(cam)

	# Status LED splash — the only "eyes": a pool of dim neutral light that
	# moves with the chassis. Reading a wall means driving into its edge of
	# the pool; the scanner carries everything farther.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.75, 0.8, 0.9)
	lamp.light_energy = 0.42
	lamp.omni_range = 3.4
	lamp.shadow_enabled = true
	lamp.omni_attenuation = 2.2
	lamp.light_volumetric_fog_energy = 0.0
	lamp.position = Vector3(0, 0.35, -0.1)
	add_child(lamp)
	floor_snap_length = 0.5


func set_controlled(on: bool) -> void:
	controlled = on
	if on:
		if live_view:
			cam.make_current()
		motor = Sfx.loop("motor", -30.0)
	elif motor != null:
		motor.stop()
		motor.queue_free()
		motor = null


## Give each chassis a distinct status LED so two parked bots are readable in
## the dark and in the HUD fleet line. Called by main after the node is built.
func configure_bot(index: int) -> void:
	bot_index = index
	if _led == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.albedo_color = Color(1.0, 0.62, 0.22) if index % 2 == 0 \
			else Color(0.36, 0.82, 1.0)
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 2.2
	_led.material = mat


func _physics_process(delta: float) -> void:
	if not controlled or GameState.paused:
		if motor != null:
			motor.volume_db = -34.0
		return

	# Carried: no input, no drain, no tether. The body is a passenger; the
	# camera stays current so the video feed keeps showing the ride.
	if carried:
		velocity = Vector3.ZERO
		if motor != null:
			motor.volume_db = -34.0
			motor.pitch_scale = 0.82
		return

	battery = maxf(battery - BATTERY_RATE * delta, 0.0)
	if battery <= 0.0:
		battery_dead.emit()

	cam.rotation.x = 0.0
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var hurry := Input.is_action_pressed("hurry") and input.length() > 0.05
	var speed := HURRY_SPEED if hurry else WALK_SPEED

	rotate_y(-input.x * TURN_RATE * delta)
	# Tank drive: steer (x) is pure yaw, throttle (y) is pure forward.
	# The old single-vector blend crab-walked sideways while turning — a
	# turning crawler that also slides is a machine fighting itself.
	var target := global_transform.basis * Vector3(0.0, 0.0, input.y) * speed
	var damp := ACCEL if target.length() > 0.2 else 2.2
	velocity.x = lerpf(velocity.x, target.x, minf(delta * damp, 1.0))
	velocity.z = lerpf(velocity.z, target.z, minf(delta * damp, 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()

	_scrape_cd = maxf(_scrape_cd - delta, 0.0)
	_check_scrapes()
	_tether()
	_motor_noise(delta)

	if motor != null:
		var norm := Vector2(velocity.x, velocity.z).length() / HURRY_SPEED
		motor.volume_db = lerpf(motor.volume_db, -30.0 + norm * 14.0,
				minf(delta * 8.0, 1.0))
		# Load feedback: the crawler labors as it hurries. The pitch lags the
		# speed a little, which reads as strain rather than gear selection.
		var target_pitch := 0.82 + norm * 0.5 + (0.06 if hurry else 0.0)
		motor.pitch_scale = lerpf(motor.pitch_scale, target_pitch,
				minf(delta * 6.0, 1.0))


## Continuous motor presence: while the crawler is actually rolling it posts a
## soft noise pulse. Stop moving and the pulse stops, which is the player's
## main lever against the new hearing model. Wall scrapes remain louder.
func _motor_noise(delta: float) -> void:
	_motor_noise_t = maxf(_motor_noise_t - delta, 0.0)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed < 0.3 or _motor_noise_t > 0.0:
		return
	_motor_noise_t = MOTOR_NOISE_INTERVAL
	var loud := clampf(0.12 + (hspeed / HURRY_SPEED) * 0.18, 0.0, 0.30)
	NoiseBus.emit_noise(global_position, loud, self)


## Wall contact at speed = noise you (and the hosts) hear.
func _check_scrapes() -> void:
	if _scrape_cd > 0.0:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var into := -velocity.dot(col.get_normal())
		if into > 0.55:
			_scrape_cd = 0.35
			Sfx.play("scrape" if into < 1.2 else "thud",
					col.get_position(), -4.0, clampf(1.4 - into * 0.35, 0.7, 1.4))
			NoiseBus.emit_noise(col.get_position(), clampf(0.25 + into * 0.2, 0.0, 0.85))
			break


## Soft tether: strip outward velocity, gently pull home; hard wrench if the
## overflow is large (should not happen in normal play — it is a failsafe).
func _tether() -> void:
	var to_anchor := anchor_pos - global_position
	var d := to_anchor.length()
	if d <= MAX_TETHER:
		return
	var dir := to_anchor / d
	var outward := velocity.dot(-dir)
	if outward > 0.0:
		velocity -= (-dir) * outward      # kill the radial-out component
	var overflow := d - MAX_TETHER
	if overflow > 4.0:
		global_position = anchor_pos - dir * (MAX_TETHER - 0.2)
	else:
		velocity += dir * clampf(overflow * 1.5, 0.0, 3.0)
