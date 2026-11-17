extends Node
## Debug vision probe (F4): clean colour feed on any chassis, low-light
## amplification, and ghosted hostile bodies. Also proves the normal stills /
## live-feed rules return when the toggle is pressed again.
##
## Run: godot --headless --path . res://tests/debug_vision.tscn

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_failed = true


func _press_f4(main) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F4
	ev.keycode = KEY_F4
	ev.pressed = true
	main._input(ev)


func _run() -> void:
	await get_tree().physics_frame
	PSXLook.reset_to_defaults(false)
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 5:
		await get_tree().physics_frame
	main._on_start_clicked.call_deferred()
	for _i in 10:
		await get_tree().physics_frame

	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	var d = main.drone
	_check(d != null, "a chassis launches for the debug probe")
	_check(not main._live_feed_active(), "no module yet: the normal feed is stills")
	_check(main.hud._lens.visible, "no module yet: the black lens is up")

	# --- F4 ON: clean colour feed even with no module ---------------------
	_press_f4(main)
	for _i in 4:
		await get_tree().physics_frame
	_check(main.debug_vision, "F4 turns debug vision on")
	_check(main._live_feed_active(), "debug vision forces the live feed gate open")
	_check(d.live_view, "the chassis is armed for camera handoff")
	_check(main.world.get_viewport().get_camera_3d() == d.cam,
			"the drone camera is the viewport with no module fitted")
	_check(main.hud._debug_view, "the HUD knows it is in debug view")
	_check(not main.hud._live.visible,
			"the tube shader is bypassed: raw full-colour video")
	_check(not main.hud._lens.visible, "no black lens in debug vision")
	_check(main.hud._pilot_status.text.contains("DEBUG"),
			"the status line reads DEBUG")
	_check(main._env != null and main._env.ambient_light_energy > 1.0,
			"low-light ambient is raised (%.2f)"
			% (main._env.ambient_light_energy if main._env != null else -1.0))
	_check(main._env != null and main._env.fog_density < 0.01,
			"fog is cleared for visibility")
	_check(main._env != null and main._env.tonemap_exposure > 1.0,
			"exposure is raised for the dark hold")
	_check(d.lamp.omni_range > 15.0,
			"the debug lamp opens to %.0f m" % d.lamp.omni_range)
	_check(main.processor.ghosted, "the Processor is ghosted")
	_check(main.stalker != null and main.stalker.ghosted,
			"the engine-room Stalker is ghosted")

	# --- Ghosted hunter ----------------------------------------------------
	var h = main._host(Vector3(0.0, 0.2, -19.0),
			[Vector3(0.0, 0.0, -19.0), Vector3(0.0, 0.0, -24.0)])
	_check(h.ghosted, "hosts spawned during debug are ghosted")
	h.drone = d
	d.global_position = Vector3(0.0, 0.32, -21.0)
	d.velocity = Vector3(0.0, 0.0, -2.0)
	h.global_position = Vector3(0.0, 0.2, -19.0)
	h.rotation.y = 0.0
	await get_tree().physics_frame
	_check(not h._can_see_drone(),
			"a moving drone is invisible to a ghosted hunter")
	var state_before: int = h.state
	NoiseBus.emit_noise(d.global_position, 1.0)
	await get_tree().physics_frame
	_check(h.state == state_before,
			"ghosted hunters ignore even a loud drone noise")

	# --- F4 OFF: normal rules return --------------------------------------
	_press_f4(main)
	for _i in 4:
		await get_tree().physics_frame
	_check(not main.debug_vision, "F4 turns debug vision off")
	_check(not main._live_feed_active(), "without the module the feed returns to stills")
	_check(not d.live_view, "camera handoff is disarmed again")
	_check(main.world.get_viewport().get_camera_3d() == main.player.cam,
			"the player camera returns with the module absent")
	_check(main.hud._lens.visible, "the black lens returns")
	_check(not h.ghosted and not main.processor.ghosted,
			"hostile bodies are no longer ghosted")
	_check(main.stalker != null and not main.stalker.ghosted,
			"the engine Stalker is no longer ghosted")
	_check(main._env != null and main._env.ambient_light_energy < 0.5,
			"low-light ambient is restored (%.2f)"
			% (main._env.ambient_light_energy if main._env != null else -1.0))
	_check(d.lamp.omni_range < 10.0, "the lamp returns to normal range")

	# --- With the module fitted, debug still cleans and restores the tube --
	main._camera_installed = true
	d.live_view = true
	d.set_controlled(true)
	main._bind_active()
	for _i in 4:
		await get_tree().physics_frame
	_check(main._live_feed_active(), "the real module unlocks the live feed")
	_check(main.hud._live.visible, "the normal tube shader is visible")
	_press_f4(main)
	for _i in 4:
		await get_tree().physics_frame
	_check(main.hud._debug_view and not main.hud._live.visible,
			"debug strips the shader even with a module fitted")
	_press_f4(main)
	for _i in 4:
		await get_tree().physics_frame
	_check(not main.hud._debug_view and main.hud._live.visible,
			"turning debug off restores the module's tube")

	# --- Any chassis in the fleet, not just the first ----------------------
	main._deploy_cd = 0.0
	main._deploy_drone()
	for _i in 4:
		await get_tree().physics_frame
	_check(main.drones.size() == 2, "a second chassis deploys")
	_check(main.drone.live_view and main.drone.cam.is_current(),
			"the newly linked chassis inherits the live/debug feed rules")

	print("DEBUG VISION %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
