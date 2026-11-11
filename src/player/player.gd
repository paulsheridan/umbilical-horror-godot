extends CharacterBody3D
## First-person survivor. The suit is heavy: slow walk, no jump, loud boots.
## Every footstep posts to the Noise bus — this is the habit the whole game
## is built on later (drones are proxies for this body).

signal interact_pressed
signal leave_requested
signal focus_changed(prompt: String)
signal hud_message(text: String)

const WALK_SPEED := 2.55
const HURRY_SPEED := 4.1
const ACCEL := 9.0
const GRAVITY := 14.0
const MOUSE_SENS := 0.0021
const REACH := 2.7          # interact ray length, meters

var cam: Camera3D
var focus = null            # Interactable under the point of aim, or null

var _pitch := 0.0
var _bob_t := 0.0
var _step_acc := 0.0
var _hurry := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4   # world + interactables

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	var head := Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 74.0
	cam.near = 0.05
	head.add_child(cam)
	cam.make_current()
	floor_snap_length = 0.5

	# Faint eye-accommodation fill, per hallway-demo: not a flashlight, just
	# enough shading nearby that silhouettes read at all. No volumetric pump.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.60, 0.70)
	fill.light_energy = 0.22
	fill.omni_range = 4.0
	fill.shadow_enabled = false
	fill.omni_attenuation = 2.0
	fill.light_volumetric_fog_energy = 0.0
	fill.position = Vector3(0, 1.2, 0.3)
	add_child(fill)


func _input(event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		if OS.get_environment("UMBILICAL_INPUT_DEBUG") != "":
			print("INPUT_DEBUG: motion event while NOT captured (mode=%d)" % Input.get_mouse_mode())
		return
	if event is InputEventMouseMotion:
		if GameState.sortie == GameState.Sortie.PILOTING:
			return   # the chair does not turn your body
		if OS.get_environment("UMBILICAL_INPUT_DEBUG") != "":
			print("INPUT_DEBUG: motion rel=%s (captured)" % event.relative)
		rotate_y(-event.relative.x * MOUSE_SENS)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event.is_action_pressed("interact") and not event.is_echo():
		# In the chair, E means "stand up". Dispatch is single-owner: main
		# performs the focus interact for every on-foot press.
		if GameState.sortie == GameState.Sortie.PILOTING:
			leave_requested.emit()
		else:
			_press_interact()


## The actual interact dispatch (echo-filtered upstream). Callable directly:
## the headless autotest cannot capture the mouse, so it routes through here.
func _press_interact() -> void:
	interact_pressed.emit()


func _physics_process(delta: float) -> void:
	cam.rotation.x = _pitch

	# While the hand-copy map is up, your body is still — reading, not walking.
	if GameState.map_open:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# While piloting, this body is parked: no input, no footsteps, no drift
	# of attention. The Noise bus stays quiet because you stay quiet.
	if GameState.sortie == GameState.Sortie.PILOTING:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var moving := input.length() > 0.05
	_hurry = Input.is_action_pressed("hurry") and moving
	var speed := HURRY_SPEED if _hurry else WALK_SPEED

	# Standard FPS controls: A/D strafe (never yaw), W/S forward/back, and
	# the mouse looks freely at all times — including mid-stride. Walking
	# direction follows the body, so strafing and looking compose normally.
	var wish := transform.basis * Vector3(input.x, 0.0, input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target_h := wish * speed
	velocity.x = lerpf(velocity.x, target_h.x, minf(delta * ACCEL, 1.0))
	velocity.z = lerpf(velocity.z, target_h.z, minf(delta * ACCEL, 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()

	# --- Head bob + footsteps (both live here, post move_and_slide) ----------
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob_t += hspeed * delta * 1.85
		_step_acc += hspeed * delta
		# Cadence tuned for the heavy suit: a step roughly every 0.65 s at walk,
		# 0.75 s at hurry — slower than a game where you sprint everywhere.
		var threshold := 1.95 if _hurry else 1.65
		if _step_acc >= threshold:
			_step_acc = 0.0
			var metal := randf() < 0.22
			Sfx.play("step_metal" if metal else "step", Sfx.CENTER,
					-9.0 if _hurry else -13.0, randf_range(0.9, 1.08))
			# The suit makes you known. Drones will inherit this economy.
			NoiseBus.emit_noise(global_position, 0.5 if _hurry else 0.32)

	var bob := Vector3(cos(_bob_t * 0.5) * 0.008, absf(sin(_bob_t)) * 0.02, 0.0)
	cam.position = bob


func _process(_delta: float) -> void:
	# --- Focus: what's under the point of aim? (only when walking the bay) ---
	if GameState.sortie == GameState.Sortie.PILOTING or GameState.map_open:
		return
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * REACH, 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var new_focus = hit.get("collider") if hit.size() > 0 else null
	if new_focus != focus:
		focus = new_focus
		if focus != null:
			focus_changed.emit("[E] %s" % focus.prompt)
		else:
			focus_changed.emit("")


func _on_interact_pressed() -> void:
	# Wired in main; kept as a method so M1 can gate on sortie state cleanly.
	if focus == null:
		return
	var text: String = focus.interact()
	if text != "":
		Sfx.play("tick", Sfx.CENTER, -14.0, randf_range(0.9, 1.05))
		hud_message.emit(text)
