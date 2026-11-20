extends CharacterBody3D
## The remote drone body (M1: blind-era crawler — no camera, motor, tether).
## Controlled only while GameState.sortie == PILOTING. Heavy, slow, loud:
## scrapes post to NoiseBus, and the tether constrains position softly.
## Battery drains in real time; at zero the winch hauls it home blind.
## Each chassis keeps its own cargo, heading and charge; `controlled` is true
## only for the bot the player currently holds the link to.
##
## The weak omni lamp is the emergency status light. The real flashlight is a
## recovered add-on: a narrow SpotLight3D on a sprung mount that lags and kicks
## when the crawler starts, stops or turns, instead of god-lighting the room.

signal battery_dead

const MAX_TETHER := 36.0
const WALK_SPEED := 1.9
const HURRY_SPEED := 2.6
const ACCEL := 3.0
const TURN_RATE := 1.7
const GRAVITY := 12.0
const BATTERY_RATE := 0.22   # %/s -> ~7.5 min sortie
const MOTOR_NOISE_INTERVAL := 0.9   # drive = heard; stop = silence

# Flashlight mount. A critically damped-ish spring holds the beam near centre;
# onset/stop impulses push it off-axis so the light has mass without turning
# every frame into camera shake.
const FL_STIFF := 150.0
const FL_DAMP := 20.0
const FL_START_KICK := 0.075
const FL_STOP_KICK := 0.045
const FL_TURN_KICK := 0.060
const FL_TURN_STOP_KICK := 0.040
const FL_ACCEL_KICK := 0.012
const FL_AIM_X := 0.20       # radians of local yaw
const FL_AIM_Y := 0.15       # radians of local pitch

# Fluent refs (set up in _ready; no class-cache globals relied on).
const Mats := preload("res://src/mats.gd")

var controlled := false
## First drone iteration: live drone view is OFF (main sets this false). The
## camera node still exists because the still-photo SubViewport copies its
## transform for each exposure; it just never becomes the main viewport camera.
## Set true to restore the live feed.
var live_view := false
var battery := 100.0
# Battery is a one-way trip: emit the dead signal on the transition only, not
# every physics frame once the charge sits at zero.
var _battery_dead_fired := false
var anchor_pos := Vector3.ZERO
var dock_pos := Vector3.ZERO
var cam: Camera3D
var motor: AudioStreamPlayer = null
## Per-chassis strike damage. The first host contact breaks the lens and knocks
## the body, but the bot stays pilotable; the next contact destroys it.
var camera_damaged := false
var cam_damage_pitch := 0.0   # radians; > 0 = knocked upward, never down
var cam_damage_yaw := 0.0     # radians; always < 90 degrees in magnitude
## Per-chassis state. The fleet shares one active link but each bot keeps its
## own position, heading, charge and cargo while the player is elsewhere.
var cargo := ""
var bot_index := 0
## True while the Collector is carrying this chassis. The link, camera and
## charge stay live; only self-movement is suspended. The Collector places the
## body each frame, and the player can watch the whole ride.
var carried := false
var lamp: OmniLight3D = null
var flashlight: SpotLight3D = null
var flashlight_pivot: Node3D = null
var flashlight_installed := false
var flashlight_on := true
var _fl_lens: CSGShape3D = null
var _led: CSGBox3D = null

var _scrape_cd := 0.0
var _motor_noise_t := 0.0
var _fl_aim := Vector2.ZERO      # x = local yaw, y = local pitch
var _fl_vel := Vector2.ZERO
var _fl_prev_speed := 0.0
var _fl_prev_yaw := 0.0
var _fl_prev_yaw_rate := 0.0


func _exit_tree() -> void:
	# Release the motor loop cleanly on teardown/shutdown (Sfx._exit_tree
	# handles the global hum, the drone's loop lives here).
	set_controlled(false)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	# Chassis, tracks, camera barrel and status lamp are authored in
	# scenes/actors/drone.tscn; this script owns behaviour only.
	cam = $Head/Cam
	_led = $Chassis/LED
	lamp = $Lamp
	flashlight_pivot = get_node_or_null("Flashlight") as Node3D
	flashlight = get_node_or_null("Flashlight/Beam") as SpotLight3D
	_fl_lens = get_node_or_null("Flashlight/Lens") as CSGShape3D
	floor_snap_length = 0.5
	_fl_prev_yaw = rotation.y
	set_flashlight(flashlight_installed)

## Toggle the recovered add-on. The mount stays on the chassis; only the beam
## and the lens light cut when it is switched off. The emergency omni returns
## to its weak pool so the pilot can still creep in the dark.
func set_flashlight(on: bool) -> void:
	flashlight_installed = on
	if flashlight_pivot != null:
		flashlight_pivot.visible = on
		flashlight_pivot.rotation = Vector3.ZERO
	_apply_flashlight_state()
	if on:
		_fl_prev_yaw = rotation.y
		_fl_prev_speed = 0.0
		_fl_prev_yaw_rate = 0.0
	else:
		_fl_reset_spring()
		_fl_prev_yaw_rate = 0.0


## L. The flashlight is a trade: the beam is real sight-range for the hosts.
func set_flashlight_enabled(on: bool) -> void:
	flashlight_on = on
	_apply_flashlight_state()


func toggle_flashlight() -> bool:
	if not flashlight_installed:
		return false
	set_flashlight_enabled(not flashlight_on)
	return flashlight_on


func _apply_flashlight_state() -> void:
	var lit := flashlight_installed and flashlight_on
	if flashlight != null:
		flashlight.visible = lit
	if _fl_lens != null:
		_fl_lens.visible = lit
	if lamp != null:
		lamp.light_energy = 0.0 if lit else 0.42
	if not lit:
		_fl_reset_spring()


## Park the beam: kill any stored aim and offset. Shared by every "light is
## off / link is down" path so the mount always returns to dead centre.
func _fl_reset_spring() -> void:
	_fl_aim = Vector2.ZERO
	_fl_vel = Vector2.ZERO
	if flashlight_pivot != null:
		flashlight_pivot.rotation = Vector3.ZERO

func set_controlled(on: bool) -> void:
	controlled = on
	_fl_prev_speed = 0.0
	_fl_prev_yaw = rotation.y
	_fl_prev_yaw_rate = 0.0
	if not on:
		_fl_reset_spring()
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


## The stalker's first hit: the lens is knocked and the chassis shoved, but the
## bot is still fully pilotable. One strike per chassis — the next contact kills.
func apply_camera_damage(rng: RandomNumberGenerator, push_dir: Vector3) -> bool:
	if camera_damaged:
		return false
	camera_damaged = true
	# Always above the horizontal plane: a broken lens looks at the ceiling,
	# never back at its own body, so the feed still reads as a drone view.
	cam_damage_pitch = rng.randf_range(0.25, 0.6)
	# A random yaw either way, capped under 90 degrees so the world ahead is
	# still in frame.
	cam_damage_yaw = signf(rng.randf_range(-1.0, 1.0)) \
			* rng.randf_range(0.1, 1.45)
	rotation.y += rng.randf_range(-0.9, 0.9)
	# An impulse, never a teleport: physics resolves the shove against walls.
	var push := Vector3(push_dir.x, 0.0, push_dir.z)
	velocity += push.normalized() * 2.2
	if cam != null:
		cam.rotation.x = cam_damage_pitch
		cam.rotation.y = cam_damage_yaw
	return true


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
	if battery <= 0.0 and not _battery_dead_fired:
		_battery_dead_fired = true
		battery_dead.emit()

	# The damaged lens offset must survive this per-frame reset; yaw is never
	# touched here, so a broken camera stays broken until the chassis dies.
	cam.rotation.x = cam_damage_pitch
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
	# One horizontal-speed read per frame, taken after the tether settles the
	# velocity. Motor volume, motor noise and the lamp spring all share it.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_motor_noise(delta, hspeed)
	_flashlight_motion(delta, hspeed)

	if motor != null:
		var norm := hspeed / HURRY_SPEED
		motor.volume_db = lerpf(motor.volume_db, -30.0 + norm * 14.0,
				minf(delta * 8.0, 1.0))
		# Load feedback: the crawler labors as it hurries. The pitch lags the
		# speed a little, which reads as strain rather than gear selection.
		var target_pitch := 0.82 + norm * 0.5 + (0.06 if hurry else 0.0)
		motor.pitch_scale = lerpf(motor.pitch_scale, target_pitch,
				minf(delta * 6.0, 1.0))


## The flashlight has inertia. Spring the beam back to centre and inject small
## impulses when the crawler gets rolling, brakes, or starts/stops a turn. The
## offset is visible but bounded: a hand-held lamp, not a broken gimbal.
func _flashlight_motion(delta: float, speed: float) -> void:
	if flashlight_pivot == null or not flashlight_installed or not flashlight_on \
			or delta <= 0.0:
		return
	var yaw := rotation.y
	var yaw_delta := wrapf(yaw - _fl_prev_yaw, -PI, PI)
	var yaw_rate := yaw_delta / delta
	var accel := (speed - _fl_prev_speed) / delta
	var yaw_accel := (yaw_rate - _fl_prev_yaw_rate) / delta

	# Onsets: the mount lags the chassis rather than tracking it rigidly.
	if speed > 0.18 and _fl_prev_speed <= 0.18:
		_fl_vel.y -= FL_START_KICK
	elif speed < 0.12 and _fl_prev_speed >= 0.12:
		_fl_vel.y += FL_STOP_KICK
	if absf(yaw_rate) > 0.35 and absf(_fl_prev_yaw_rate) <= 0.35:
		_fl_vel.x -= signf(yaw_rate) * FL_TURN_KICK
	elif absf(yaw_rate) < 0.18 and absf(_fl_prev_yaw_rate) >= 0.35:
		_fl_vel.x += signf(_fl_prev_yaw_rate) * FL_TURN_STOP_KICK

	# A hard lurch (accelerating or braking) tips the beam further.
	if absf(accel) > 1.0:
		_fl_vel.y -= clampf(accel * FL_ACCEL_KICK, -0.42, 0.42)
	# Steering fight adds a little yaw tremor while the tracks are loaded.
	if absf(yaw_accel) > 5.0:
		_fl_vel.x += clampf(yaw_accel * 0.003, -0.16, 0.16)

	# Spring toward centre. Explicit integration is stable at physics rates.
	_fl_vel += (-_fl_aim * FL_STIFF - _fl_vel * FL_DAMP) * delta
	_fl_aim += _fl_vel * delta
	if absf(_fl_aim.x) > FL_AIM_X:
		_fl_aim.x = clampf(_fl_aim.x, -FL_AIM_X, FL_AIM_X)
		_fl_vel.x *= -0.18
	if absf(_fl_aim.y) > FL_AIM_Y:
		_fl_aim.y = clampf(_fl_aim.y, -FL_AIM_Y, FL_AIM_Y)
		_fl_vel.y *= -0.18
	flashlight_pivot.rotation = Vector3(_fl_aim.y, _fl_aim.x, 0.0)

	_fl_prev_speed = speed
	_fl_prev_yaw = yaw
	_fl_prev_yaw_rate = yaw_rate


## Continuous motor presence: while the crawler is actually rolling it posts a
## soft noise pulse. Stop moving and the pulse stops, which is the player's
## main lever against the new hearing model. Wall scrapes remain louder.
func _motor_noise(delta: float, hspeed: float) -> void:
	_motor_noise_t = maxf(_motor_noise_t - delta, 0.0)
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
