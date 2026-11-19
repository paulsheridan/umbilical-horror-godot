extends Node
## Headless autotest for the M0 shell. Runs like the real game (with autoloads).
## Run:  godot --headless --path . res://tests/autotest.tscn
## Validates: shell boots, bay built with interactables, heavy movement works
## and posts to NoiseBus, focus/interact resolves a prompt + message line,
## meters tick while GameState is running.

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame

	PSXLook.reset_to_defaults(false)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		return _fail("main.tscn failed to load")
	var main: Node3D = main_scene.instantiate()
	add_child(main)
	for _i in 5:
		await get_tree().physics_frame
	main._on_start_clicked.call_deferred()
	for _i in 12:
		await get_tree().physics_frame

	# --- Shell ----------------------------------------------------------------
	_check(main.player != null, "player exists")
	if main.player != null:
		_check(main.player.cam != null, "player has a working camera")
	_check(main.level != null, "fab bay built")

	var interactables := 0
	if main.level != null:
		for child in main.level.get_children():
			if child is StaticBody3D and child.has_method("interact"):
				interactables += 1
	_check(interactables >= 6, "found %d interactables in the bay (want >= 6)" % interactables)

	_check(Sfx._streams.has("hum"), "Sfx built the bay hum loop")
	_check(Sfx._streams.has("knock"), "Sfx built the hull knock")
	_check(GameState.running, "GameState running after start")

	# --- Processor wing / Collector feed -------------------------------------
	_check(main.processor != null, "the Processor is spawned in its chamber")
	_check(main.collector != null, "the Collector is resident in the ship")
	if main.processor != null:
		_check(main.processor.global_position.distance_to(main.ship.PROCESSOR_POS) < 0.2,
				"the Processor is pinned at its authored mark")
		_check(main.processor.pile == main.ship.processor_pile,
				"the Processor is fed from its own pile")
	if main.collector != null:
		_check(main.collector.bots == main.drones,
				"the Collector shares the live fleet array")
		_check(main.collector.deposit_pos.distance_to(main.ship.PROCESSOR_PILE) < 0.1,
				"the Collector now deposits at the Processor pile")
		_check(main.collector.bot_drop_pos.distance_to(main.ship.PROCESSOR_DROP) < 0.1,
				"the Collector's bot drop is on the Processor's mark")
	var route_reaches := false
	for wp in main.COLLECTOR_ROUTE:
		var d := Vector2(wp.x - main.ship.PROCESSOR_PILE.x,
				wp.z - main.ship.PROCESSOR_PILE.z).length()
		if d < 0.2:
			route_reaches = true
	_check(route_reaches, "the Collector's route reaches the Processor pile")

	# --- Heavy movement + Noise bus ------------------------------------------
	if main.player != null:
		var start_pos: Vector3 = main.player.global_position
		Input.action_press("move_forward")
		for _i in 90:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var moved: float = main.player.global_position.distance_to(start_pos)
		_check(moved > 0.5, "player walked %.2f m under input" % moved)
		_check(NoiseBus.count > 0, "footsteps posted %d noise events" % NoiseBus.count)

		# FPS-controls regression: A/D strafe (no yaw), W walks — mouse look is
		# independent and unaffected by movement, and must stay that way.
		main.player.global_position = Vector3(4.2, 0.2, 2.8)
		main.player.velocity = Vector3.ZERO
		var pyaw0: float = main.player.rotation.y
		var ppos0: Vector3 = main.player.global_position
		Input.action_press("move_left")
		for _i in 70:
			await get_tree().physics_frame
		Input.action_release("move_left")
		var pyaw: float = absf(main.player.rotation.y - pyaw0)
		var pmoved: float = main.player.global_position.distance_to(ppos0)
		_check(pyaw < 0.001, "A/D strafe does not yaw the body (%.3f rad)" % pyaw)
		_check(pmoved > 0.8, "A strafes the body laterally (%.2f m)" % pmoved)

	# --- Focus + interact ------------------------------------------------------
	if main.player != null and main.level != null:
		main.player.global_position = Vector3(3.0, 0.05, 0.0)
		main.player.rotation.y = PI * 0.5   # facing -X, toward the map table
		main.player._pitch = -0.25
		main.player.cam.rotation.x = main.player._pitch
		for _i in 10:
			await get_tree().physics_frame
		_check(main.player.focus != null, "focus resolves an interactable")
		if main.player.focus != null:
			main._on_interact_pressed()
			await get_tree().physics_frame
			_check(main._map_open, "E at the map table opens the map")
			main._close_map()
			await get_tree().physics_frame

	# --- Meters tick -----------------------------------------------------------
	var o2_before: float = GameState.o2
	for _i in 120:
		await get_tree().physics_frame
	_check(GameState.o2 < o2_before,
			"meters tick while running (%.5f < %.5f)" % [GameState.o2, o2_before])

	# --- M1: sortie launch / drive / tether / reel -----------------------------
	_check(InputMap.has_action("reel"), "reel action is mapped (R)")
	_check(InputMap.has_action("flashlight"), "flashlight action is mapped (L)")
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(GameState.sortie == GameState.Sortie.PILOTING, "sortie is PILOTING after launch")
	if main.drone == null:
		_fail("drone not deployed on launch")
	else:
		# Before the salvage: radar is the display and the only camera is a
		# one-shot still. The live feed is the recovered module's perk.
		_check(main.VIDEO_FEED_ENABLED, "live-feed master gate is available")
		_check(not main._live_feed_active(), "no module yet: live feed is locked")
		_check(main.processor.drone == main.drone,
				"the Processor binds to the active chassis")
		_check(main.world.get_viewport().get_camera_3d() != main.drone.cam,
				"no live drone camera is current")
		_check(main.hud._lens.visible, "no live view: black lens while piloting")
		_check(not main.hud._blind.visible, "lamp veil is retired: radar is the display")
		_check(not main.hud._feed.visible, "no photo held at launch")
		_check(not main.hud._live.visible, "no live tube before the module")
		_check(main.hud._scanner.visible, "radar is visible as the primary display")
		_check(main.hud._desk.visible and main.hud._cam_window.visible
				and main.hud._radar_window.visible,
				"the pilot desktop shows separate optics and radar windows")
		_check((main.hud._cam_window.anchor_right
				- main.hud._cam_window.anchor_left) >= 0.6
				and (main.hud._radar_window.anchor_right
				- main.hud._radar_window.anchor_left) <= 0.25
				and (main.hud._radar_window.anchor_bottom
				- main.hud._radar_window.anchor_top) <= 0.5,
				"the optics window is large and the radar is a small inset in still mode")
		_check(main.SHUTTER_TIME >= 4.0,
				"still camera has a slow recharge (%.1f s)" % main.SHUTTER_TIME)
		_check(main._feed_vp != null
				and main._feed_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"still-camera viewport exists but is not rendering live")
		_check(main._feed_attrs != null
				and not main._feed_attrs.dof_blur_far_enabled,
				"a still exposure is focused far")

		# --- Fleet: one chassis at launch, more deployed on demand ----------
		_check(main.drones.size() == 1, "one chassis deploys at launch")
		_check(InputMap.has_action("swap_drone"), "swap action is mapped (Q)")
		_check(InputMap.has_action("deploy_drone"), "deploy action is mapped (B)")
		_check(main.hud._fleet.visible and main.hud._fleet.text.contains("BOT 1")
				and not main.hud._fleet.text.contains("BOT 2"),
				"the HUD fleet line lists only the deployed chassis")
		_check(main.hud._fleet.text.contains("[B] DEPLOY"),
				"the fleet line advertises one-at-a-time deployment")
		var lead = main.drone
		var lead_pos: Vector3 = lead.global_position
		# Q with a single chassis is a no-op, not a phantom swap.
		main._swap_cd = 0.0
		main._cycle_drone()
		for _i in 3:
			await get_tree().physics_frame
		_check(main.drone == lead, "Q does nothing with one chassis")

		# Deploy through the real B key path. One press, one new bot.
		var bev := InputEventKey.new()
		bev.physical_keycode = KEY_B
		bev.keycode = KEY_B
		bev.pressed = true
		main._input(bev)
		for _i in 4:
			await get_tree().physics_frame
		_check(main.drones.size() == 2, "B deploys exactly one more chassis")
		var second = main.drones[1]
		_check(second != lead and second.bot_index == 1,
				"the deployed chassis is a distinct BOT 2")
		var second_start: Vector3 = second.global_position
		_check(main.drone == second,
				"the link moves to the newly deployed chassis")
		_check(not lead.controlled and second.controlled,
				"exactly one chassis takes input")
		_check(main.scanner.drone == second and main.processor.drone == second,
				"scanner and the Processor bind to the deployed chassis")
		# A second press at the cap must not deploy a third body.
		main._deploy_cd = 0.0
		main._deploy_drone()
		for _i in 3:
			await get_tree().physics_frame
		_check(main.drones.size() == 2, "the fleet cap blocks a third chassis")

		# Q cycles back to the first. The parked bot neither moves nor drains.
		main._swap_cd = 0.0
		main._cycle_drone()
		for _i in 3:
			await get_tree().physics_frame
		_check(main.drone == lead, "Q cycles back to the first chassis")
		_check(main.scanner.drone == lead, "scanner follows the link back")
		_check(lead.global_position.distance_to(lead_pos) < 0.15,
				"the parked chassis does not move when the link leaves")
		var parked_batt: float = second.battery
		for _i in 90:
			await get_tree().physics_frame
		_check(is_equal_approx(second.battery, parked_batt),
				"inactive chassis holds its charge")
		_check(lead.battery < 100.0, "the linked chassis is the one draining")

		# The deployed chassis must be drivable out of its cradle.
		main._swap_cd = 0.0
		main._cycle_drone()
		for _i in 3:
			await get_tree().physics_frame
		_check(main.drone == second, "Q reaches the deployed chassis")
		Input.action_press("move_forward")
		for _i in 50:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for _i in 12:
			await get_tree().physics_frame
		_check(second.global_position.distance_to(second_start) > 0.5,
				"the deployed chassis can drive out of its cradle")

		# Q through the real event path must transfer the link, not just the
		# helper. This is what a player presses.
		main._swap_cd = 0.0
		var qev := InputEventKey.new()
		qev.physical_keycode = KEY_Q
		qev.keycode = KEY_Q
		qev.pressed = true
		main._input(qev)
		for _i in 4:
			await get_tree().physics_frame
		_check(main.drone == lead, "a real Q key press transfers the link")
		main._swap_cd = 0.0

		# Collector pickup: the chassis is cargo, not a kill. The link, the
		# scanner and the pilot state all survive the lift.
		var col = main.collector
		var lead_before_pos: Vector3 = lead.global_position
		var lead_before_yaw: float = lead.rotation.y
		col.global_position = lead.global_position
		col._pickup_cd = 0.0
		for _i in 4:
			await get_tree().physics_frame
		_check(col.carried_bot == lead and lead.carried,
				"the Collector lifts the linked chassis")
		_check(main.drone == lead and GameState.sortie == GameState.Sortie.PILOTING,
				"a Collector pickup does not disconnect the pilot")
		_check(lead.controlled and main.scanner.drone == lead,
				"the carried chassis keeps its link and senses")
		col.release_carried()
		col.global_position = Vector3(19.8, 0.2, -7.2)
		lead.global_position = lead_before_pos
		lead.rotation.y = lead_before_yaw
		lead.velocity = Vector3.ZERO
		await get_tree().physics_frame
		_check(not lead.carried, "release_carried hands the chassis back")

		# Control tests: hosts hold no drone ref (no interception mid-measure).
		for h in main.hosts:
			h.drone = null

		# The first drone's only camera: primary mouse -> one grainy still.
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		Input.parse_input_event(mb)
		for _i in 3:
			await get_tree().physics_frame
		_check(main._photo_count == 1, "primary mouse exposes a still on the first drone")
		_check(main.hud._feed.visible, "the still frame is displayed")
		_check(main.hud._lens.visible, "the lens stays black behind the print")
		_check(main.hud._scanner.visible and main.hud._radar_window.visible,
				"the radar stays up while a still is held")
		_check(main._photo_cd > 0.0, "one photograph drains the shutter")

		# Echo/early-tap regression: R in the first second (held key echoes or
		# an instant second tap) must not reel a just-deployed drone home.
		# (Fresh-launch grace is battery-based, so restore a full cell here:
		# the fleet exercises above took real time and drained the linked bot.)
		main.drone.battery = 100.0
		main._try_reel(false)
		main._try_reel(false)
		for _i in 30:
			await get_tree().physics_frame
		_check(main.drone != null and GameState.sortie == GameState.Sortie.PILOTING,
				"early R taps cannot reel a fresh drone")

		main.player._pitch = 0.0    # seat input parked
		var d_start: Vector3 = main.drone.global_position
		Input.action_press("move_forward")
		for _i in 120:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for _i in 90:   # let the heavy glide decay before checking
			await get_tree().physics_frame
		var d_moved: float = main.drone.global_position.distance_to(d_start)
		_check(d_moved > 1.0, "drone drove %.2f m" % d_moved)
		var v_now: float = main.drone.velocity.length()
		_check(v_now < 0.35, "drone coasts to a stop (momentum), v=%.2f" % v_now)
		_check(main.drone.battery < 100.0, "battery draining")

		# Tank-drive regression: steer (A) + drive (W) must do BOTH at once —
		# yaw the drone AND advance it. (Bug history: steer was mapped into
		# the lateral axis, so turning crab-walked and fought the drive.)
		main.drone.global_position = Vector3(0.4, 0.32, -21.0)   # open junction
		main.drone.velocity = Vector3.ZERO
		var yaw0: float = main.drone.rotation.y
		var pos_t: Vector3 = main.drone.global_position
		Input.action_press("move_forward")
		Input.action_press("move_left")
		for _i in 140:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		Input.action_release("move_left")
		var dyaw: float = absf(main.drone.rotation.y - yaw0)
		var moved_t: float = main.drone.global_position.distance_to(pos_t)
		_check(dyaw > 0.3, "turn+drive yaws the drone (%.2f rad)" % dyaw)
		_check(moved_t > 1.0, "turn+drive still advances (%.2f m)" % moved_t)
		main.drone.global_position = Vector3(-2.0, 0.32, -7.0)   # back to dock side
		main.drone.velocity = Vector3.ZERO
		for _i in 5:
			await get_tree().physics_frame

		# --- Chair persistence: E stands you up, E again resumes ------------
		# The machine must survive the chair session: same node, position,
		# heading, charge and cargo. Hosts/scanner lose the link while parked.
		var parked = main.drone
		var park_pos: Vector3 = parked.global_position
		var park_yaw: float = parked.rotation.y
		var park_batt: float = parked.battery
		main.player.leave_requested.emit()
		for _i in 6:
			await get_tree().physics_frame
		_check(main.drone == parked and is_instance_valid(parked),
				"standing up keeps the drone alive")
		_check(GameState.sortie == GameState.Sortie.IDLE, "sortie idles while you stand")
		_check(not parked.controlled, "parked drone releases the controls")
		_check(main.scanner.drone == null, "scanner goes dark while you stand")
		_check(main.processor.drone == null, "senses lose the drone's scent while you stand")
		_check(main.world.get_viewport().get_camera_3d() == main.player.cam,
				"standing up restores the player camera")
		var walk_from: Vector3 = main.player.global_position
		Input.action_press("move_forward")
		for _i in 40:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for _i in 20:
			await get_tree().physics_frame
		_check(main.player.global_position.distance_to(walk_from) > 0.25,
				"player can walk the bay after standing up")
		var batt_suspended: float = parked.battery
		for _i in 60:
			await get_tree().physics_frame
		_check(is_equal_approx(parked.battery, batt_suspended),
				"parked drone does not drain")
		_check(parked.global_position.distance_to(park_pos) < 0.05,
				"parked drone holds its position")

		# Sit again through the real chair focus/interact path.
		main.player.global_position = Vector3(-3.8, 0.05, -1.6)
		main.player.rotation.y = PI * 0.5
		main.player._pitch = -0.1
		for _i in 10:
			await get_tree().physics_frame
		_check(main.player.focus == main.level.pilot_chair, "chair is focusable after standing")
		_check(main.level.pilot_chair.prompt == "DRONE",
				"chair prompt offers to resume the parked drone")
		main.player._press_interact()
		for _i in 6:
			await get_tree().physics_frame
		_check(GameState.sortie == GameState.Sortie.PILOTING, "chair re-entry resumes piloting")
		_check(main.drone == parked, "re-entry reuses the same drone node")
		_check(main.drone.global_position.distance_to(park_pos) < 0.05,
				"drone resumes in the same place")
		_check(absf(wrapf(main.drone.rotation.y - park_yaw, -PI, PI)) < 0.05,
				"drone resumes at the same heading")
		_check(absf(main.drone.battery - park_batt) < 0.2,
				"battery preserved across the chair session")
		_check(main.world.get_viewport().get_camera_3d() != main.drone.cam,
				"no live drone view on resume before the module")
		_check(main.scanner.drone == main.drone and main.processor.drone == main.drone,
				"scanner + Processor reacquire the drone on resume")
		# Put it back on the dock side for the reel check below.
		main.drone.global_position = Vector3(-2.0, 0.32, -7.0)
		main.drone.velocity = Vector3.ZERO
		for _i in 5:
			await get_tree().physics_frame

		# Deliberate R near the dock (cooldown expired): must reel it home.
		# Send a real key event so the action map + raw-R fallback are exercised.
		var rk := InputEventKey.new()
		rk.physical_keycode = KEY_R
		rk.pressed = true
		Input.parse_input_event(rk)
		var rk_up := InputEventKey.new()
		rk_up.physical_keycode = KEY_R
		rk_up.pressed = false
		Input.parse_input_event(rk_up)
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "R near the dock reels the drone home")
	_check(GameState.sortie == GameState.Sortie.IDLE, "sortie back to IDLE after reel")
	_check(main.world.get_viewport().get_camera_3d() == main.player.cam, "player camera restored")

	# Second sortie: tether clamp + the battery-forced reel path.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(GameState.sortie == GameState.Sortie.PILOTING, "second sortie launches clean")
	if main.drone != null:
		main.drone.global_position = main.ship.dock_pos + Vector3(0, 0, 60.0)
		main.drone.velocity = Vector3.ZERO
		for _i in 40:
			await get_tree().physics_frame
		var overflow: float = main.drone.global_position.distance_to(main.ship.dock_pos)
		_check(overflow <= main.drone.MAX_TETHER + 0.6,
				"tether clamps at %.2f m (max %.0f)" % [overflow, main.drone.MAX_TETHER])
	main._try_reel(true)
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "forced reel teardown works on the second sortie")
	_check(GameState.sortie == GameState.Sortie.IDLE, "sortie back to IDLE after force reel")

	# --- M2: host rules / objective / door / caught / deliver -----------------
	_check(main.hosts.is_empty(), "Zone 1 starts threat-free: no hosts resident")

	# The opening ship carries no hunter any more. These rules still matter, so
	# the probe spawns a temporary ordinary host and tests the model directly.
	main._knock_t = 9999.0   # silence ambient lures during the measurement
	var patroller = main._host(Vector3(-2.4, 0.2, -10.0), [
		Vector3(-2.3, 0.0, -9.0), Vector3(-2.3, 0.0, -14.0),
	])
	var patrol_walk = patroller
	patrol_walk.drone = null
	patrol_walk.global_position = Vector3(-2.4, 0.2, -10.0)
	patrol_walk.reset()
	var traveled := 0.0
	var last_p: Vector3 = patrol_walk.global_position
	var wp0: int = patrol_walk._wp
	var wp_changed := false
	for _i in 480:
		await get_tree().physics_frame
		if patrol_walk._wp != wp0:
			wp_changed = true
		if _i % 60 == 0:
			traveled += patrol_walk.global_position.distance_to(last_p)
			last_p = patrol_walk.global_position
	traveled += patrol_walk.global_position.distance_to(last_p)
	_check(traveled > 3.0, "patroller wanders the halls (%.1f m in 8 s)" % traveled)
	_check(wp_changed, "patroller cycles its waypoint loop")

	# Hearing model: one quiet noise makes the host CURIOUS. It must listen,
	# not walk to the sound. This is the main leeway change.
	patroller.drone = null
	patroller.global_position = Vector3(0.0, 0.2, -29.0)
	patroller.reset()
	var quiet_pos := Vector3(0.4, 1.0, -25.0)
	NoiseBus.emit_noise(quiet_pos, 0.3)
	await get_tree().physics_frame
	_check(patroller.state == patroller.State.CURIOUS,
			"first quiet noise makes the host curious")
	var curious_start: Vector3 = patroller.global_position
	for _i in 45:   # 0.75 s: inside the listen window
		await get_tree().physics_frame
	_check(patroller.global_position.distance_to(curious_start) < 0.15,
			"curious host listens instead of walking to the noise")
	var listened := 0
	while patroller.state == patroller.State.CURIOUS and listened < 400:
		await get_tree().physics_frame
		listened += 1
	_check(patroller.state == patroller.State.PATROL,
			"curious host returns to patrol after silence")

	# A single very loud event skips the listening phase.
	patroller.global_position = Vector3(0.0, 0.2, -29.0)
	patroller.reset()
	NoiseBus.emit_noise(Vector3(0.4, 1.0, -25.0), 0.8)
	await get_tree().physics_frame
	_check(patroller.state == patroller.State.HUNT,
			"a loud bang skips the listening phase")

	# A second quiet noise commits the hunt, and the remembered target is
	# deliberately wrong: the host does not know the exact position.
	patroller.global_position = Vector3(0.0, 0.2, -29.0)
	patroller.reset()
	NoiseBus.emit_noise(Vector3(0.4, 1.0, -25.0), 0.3)
	await get_tree().physics_frame
	for _i in 90:   # 1.5 s: past ESCALATE_DELAY
		await get_tree().physics_frame
	var second_pos := Vector3(1.2, 1.0, -25.4)
	NoiseBus.emit_noise(second_pos, 0.3)
	await get_tree().physics_frame
	_check(patroller.state == patroller.State.HUNT,
			"second quiet noise starts a hunt")
	_check(patroller._hunt_target.distance_to(second_pos) > 0.15,
			"hunt target is imprecise (%.2f m off)" % patroller._hunt_target.distance_to(second_pos))

	# Host-vs-host hearing regression: two silhouettes sharing a room must not
	# summon each other with their own footsteps (the mutual-investigate loop).
	# Host steps still post to the bus, but are source-tagged and invisible to
	# other hosts. Player/drone/environment noise stays audible.
	var h0 = patroller
	var h0_wp: Array = h0.waypoints.duplicate()
	h0.waypoints = [Vector3(-2.0, 0.0, -29.0), Vector3(2.0, 0.0, -29.0)]
	h0.global_position = Vector3(-1.2, 0.2, -29.2)
	h0.state = h0.State.PATROL
	h0.reset()
	main._host(Vector3(1.2, 0.2, -29.2),
			[Vector3(2.0, 0.0, -29.0), Vector3(-2.0, 0.0, -29.0)])
	var h1 = main.hosts[1]
	h1.drone = null
	h1.reset()
	for _i in 180:
		await get_tree().physics_frame
	_check(h0.state == h0.State.PATROL and h1.state == h1.State.PATROL,
			"hosts do not hear each other's steps (states %d/%d)" % [h0.state, h1.state])
	main.hosts.erase(h1)
	h1.queue_free()
	h0.waypoints = h0_wp
	h0.global_position = Vector3(-2.4, 0.2, -10.0)
	h0.state = h0.State.PATROL
	h0.reset()

	# The galley door grinds open near the drone and stays open.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	# One spare for the cargo-transfer and survivor-catch checks below.
	main._deploy_cd = 0.0
	main._deploy_drone()
	for _i in 4:
		await get_tree().physics_frame
	_check(main.drones.size() == 2, "spare chassis deployed for the delivery run")
	if main.drone != null:
		main.drone.global_position = Vector3(-6.5, 0.32, -29.2)
		main.drone.velocity = Vector3.ZERO
		for _i in 300:   # ~5 s: grind time
			await get_tree().physics_frame
		_check(main.ship.galley_door_open, "galley door opened near the drone")
		_check(main.ship.galley_door.position.z >= main.ship.DOOR_OPEN_Z - 0.2,
				"door fully slid (z=%.1f)" % main.ship.galley_door.position.z)
		_check(main.hosts.size() == 1,
				"the galley stays empty behind the opened door (no extra body)")

		# Pickup event only: no geometry traversal through the galley seams.
		for h in main.hosts:
			h.drone = null
		main.drone.global_position = Vector3(
				main.ship.FLASHLIGHT_POS.x, 0.32, main.ship.FLASHLIGHT_POS.z)
		main.drone.velocity = Vector3.ZERO
		for _i in 20:
			await get_tree().physics_frame
		for h in main.hosts:
			h.drone = main.drone
			h.state = h.State.PATROL
		_check(main._cargo == "flashlight",
				"secured the flashlight add-on at its anchor (x=%.1f z=%.1f)"
				% [main.drone.global_position.x, main.drone.global_position.z])

		# Cargo belongs to the chassis, not the link: hop to the empty bot and
		# back, and the add-on is still on the one that picked it up.
		var cargo_bot = main.drone
		main._cycle_drone()
		for _i in 20:
			await get_tree().physics_frame
		_check(main.drone != cargo_bot and main._cargo == "",
				"the empty chassis does not inherit the other bot's cargo")
		main._cycle_drone()
		for _i in 20:
			await get_tree().physics_frame
		_check(main.drone == cargo_bot and main._cargo == "flashlight",
				"cargo persists on the chassis across the link transfer")

		# Loss: a temporary stalking host at contact takes the cargo drone.
		patroller.global_position = Vector3(1.0, 0.2, -26.0)
		main.drone.global_position = Vector3(1.3, 0.32, -26.0)
		main.drone.velocity = Vector3.ZERO
		patroller.force_stalk(main.drone.global_position)
		for _i in 40:
			await get_tree().physics_frame
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone != null, "a surviving chassis keeps the sortie alive after a catch")
	_check(main.drones.size() == 1, "the caught chassis is struck from the fleet")
	_check(main._objective_state == "pending", "carried cargo lost on catch")
	_check(GameState.sortie == GameState.Sortie.PILOTING,
			"the link hops to the survivor instead of tearing down")
	patroller.drone = null   # the test body is done hunting
	# Recall the survivor so the delivery run starts from a clean fleet.
	main._try_reel(true)
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "reeling the last chassis ends the sortie")

	# Deliver: pick up again, then reel home -> the add-on waits at the bench.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	# Deterministic delivery phase: park the patroller at the spur end and pin
	# it to PATROL (the run measures the delivery path, not hunt pacing).
	for h in main.hosts:
		h.state = h.State.PATROL
	patroller.global_position = Vector3(8.0, 0.2, -29.2)
	main.drone.global_position = Vector3(
			main.ship.FLASHLIGHT_POS.x, 0.32, main.ship.FLASHLIGHT_POS.z)
	main.drone.velocity = Vector3.ZERO
	for _i in 20:
		await get_tree().physics_frame
	_check(main._cargo == "flashlight", "objective recovered on retry")
	main.drone.global_position = main.ship.dock_pos
	main.drone.velocity = Vector3.ZERO
	for _i in 60:   # let the launch grace expire (battery-based guard)
		await get_tree().physics_frame
	main._try_reel(false)   # deliberate reel near the dock
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "delivery reel teardown")
	_check(main._flashlight_held and not main._flashlight_installed,
			"flashlight add-on delivered to the bay, waiting for the fabricator")
	_check(main._objective_state == "pending",
			"the flashlight objective stays pending until it is fitted")
	main._at_fabricator()
	await get_tree().physics_frame
	_check(main._flashlight_installed and not main._flashlight_held,
			"flashlight add-on installed at the fabricator")
	_check(main._objective_state == "none", "objective complete after fitting")

	# --- M3: video module salvage -> deliver -> install -> stills ------------
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	if main.drone != null:
		# The flashlight is fleet kit now: fitted, visible, and sprung.
		_check(main.drone.flashlight_installed
				and main.drone.flashlight_pivot != null
				and main.drone.flashlight_pivot.visible,
				"the fitted flashlight appears on the sortie chassis")
		_check(main.drone.flashlight.spot_angle <= 25.0
				and main.drone.flashlight.spot_range >= 12.0,
				"the flashlight throws a narrow, long beam (%.0f°, %.0f m)"
				% [main.drone.flashlight.spot_angle, main.drone.flashlight.spot_range])
		_check(main.drone.flashlight_on and main.drone.flashlight.visible,
				"the fitted flashlight boots switched on")
		var lev := InputEventKey.new()
		lev.physical_keycode = KEY_L
		lev.keycode = KEY_L
		lev.pressed = true
		main._input(lev)
		_check(not main.drone.flashlight_on and not main.drone.flashlight.visible,
				"L switches the flashlight off")
		main._input(lev)
		_check(main.drone.flashlight_on and main.drone.flashlight.visible,
				"L switches the flashlight back on")
		main.drone.global_position = Vector3(0.4, 0.32, -21.0)  # open junction
		main.drone.velocity = Vector3.ZERO
		main.drone.rotation.y = 0.0
		var fl_pivot: Node3D = main.drone.flashlight_pivot
		fl_pivot.rotation = Vector3.ZERO
		Input.action_press("move_forward")
		for _i in 8:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var fl_kick: float = absf(fl_pivot.rotation.x) + absf(fl_pivot.rotation.y)
		_check(fl_kick > 0.002,
				"the flashlight beam jerks when the bot starts (%.3f rad)" % fl_kick)
		for _i in 90:
			await get_tree().physics_frame
		for h in main.hosts:
			h.drone = null   # deterministic checks; no pursuits for this leg
		main.drone.global_position = Vector3(
				main.ship.CAMERA_POS.x, 0.32, main.ship.CAMERA_POS.z)
		main.drone.velocity = Vector3.ZERO
		for _i in 20:
			await get_tree().physics_frame
		_check(main._cargo == "camera", "video module recovered from the spur wreck")
		main.drone.global_position = main.ship.dock_pos
		main.drone.velocity = Vector3.ZERO
		for h in main.hosts:
			h.drone = main.drone
		for _i in 60:    # launch grace
			await get_tree().physics_frame
		main._try_reel(false)
	for _i in 150:
		await get_tree().physics_frame
	_check(main._camera_held, "video module delivered to the bay")
	_check(main._cargo == "", "cargo slot empty after delivery")
	_check(main._feed_vp != null, "still-camera viewport exists from the first launch")

	# Install the video module at the fabricator: this unlocks the live feed.
	main._at_fabricator()
	await get_tree().physics_frame
	_check(main._camera_installed, "video module installed at the fabricator")
	_check(main._feed_vp != null, "photo viewport persists after install")
	_check(main.hud._feed_enabled, "still camera remains enabled")

	# The next sortie now has LIVE video: the large optics window shows the
	# live feed, while the separate radar stays small and always readable.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(main._live_feed_active(), "installed module unlocks the live feed")
	_check(main.drone.live_view, "live camera handoff is armed")
	_check(main.world.get_viewport().get_camera_3d() == main.drone.cam,
			"live drone view is the current camera")
	_check(not main.hud._lens.visible, "live feed: no black lens")
	_check(main.hud._live.visible, "live tube filter is shown")
	_check(not main.hud._feed.visible, "live feed: no held print")
	_check(not main.hud._blind.visible, "live feed: no lamp veil")
	_check(main.hud._shutter.visible, "shutter meter still shown")
	_check(main.hud._scanner.visible, "radar stays available alongside live video")
	_check((main.hud._cam_window.anchor_right
			- main.hud._cam_window.anchor_left) >= 0.6
			and (main.hud._radar_window.anchor_right
			- main.hud._radar_window.anchor_left) <= 0.25
			and (main.hud._radar_window.anchor_bottom
			- main.hud._radar_window.anchor_top) <= 0.5,
			"the live picture is large and the radar is a small inset in live mode")
	_check(main._feed_attrs != null and main._feed_attrs.dof_blur_far_enabled,
			"the live tube is near-sighted (far focus is lost)")
	main.hud.set_live_stress(0.75, -0.5)
	_check(absf(float(main.hud._live_mat.get_shader_parameter("stress")) - 0.75) < 0.01,
			"live tube takes drive stress")
	_check(absf(float(main.hud._live_mat.get_shader_parameter("turn")) + 0.5) < 0.01,
			"live tube takes signed steering")
	main.hud.set_live_stress(0.0, 0.0)
	# Deploy the second chassis so a real catch still leaves a survivor.
	main._deploy_cd = 0.0
	main._deploy_drone()
	for _i in 4:
		await get_tree().physics_frame
	_check(main.drones.size() == 2, "second chassis joins before the interception")
	# Send a real F keypress through the input stack, not a direct call: this
	# is the path a player uses, and it must work even if the project's input
	# map was loaded before the action existed in an editor session.
	var photos_at_f: int = main._photo_count
	var fk := InputEventKey.new()
	fk.physical_keycode = KEY_F
	fk.pressed = true
	Input.parse_input_event(fk)
	for _i in 3:
		await get_tree().physics_frame
	var fk_up := InputEventKey.new()
	fk_up.physical_keycode = KEY_F
	fk_up.pressed = false
	Input.parse_input_event(fk_up)
	_check(main._photo_count == photos_at_f + 1, "F still exposes a print in live mode")
	_check(not main._feed_attrs.dof_blur_far_enabled,
			"a still exposes with clear far focus")
	_check(main.hud._feed.visible, "the print replaces only the video")
	_check(main.hud._scanner.visible and main.hud._radar_window.visible,
			"the radar stays up while a print is held")
	_check(not main.hud._lens.visible, "the lens stays clear in live mode")
	_check(main._photo_cd > 0.0, "shutter empties after a shot")
	main._take_photo()
	for _i in 2:
		await get_tree().physics_frame
	_check(main._photo_count == photos_at_f + 1, "shutter cooldown blocks a second immediate shot")
	var recharge_frames := 0
	while main._photo_cd > 0.0 and recharge_frames < 900:
		await get_tree().physics_frame
		recharge_frames += 1
	_check(main._photo_cd <= 0.0, "shutter recharges (%.1f s)" % (recharge_frames / 60.0))
	main._take_photo()
	for _i in 2:
		await get_tree().physics_frame
	_check(main._photo_count == photos_at_f + 2, "second frame after recharge")
	var hold_frames := 0
	while main._photo_show > 0.0 and hold_frames < 400:
		await get_tree().physics_frame
		hold_frames += 1
	_check(not main.hud._feed.visible, "the print drops back to live video")
	_check(main._feed_attrs.dof_blur_far_enabled,
			"the print drops back to the near-sighted live lens")
	_check(not main.hud._lens.visible, "live view returns with no black lens")
	_check(main.hud._shutter_frac >= 0.0 and main.hud._shutter_frac <= 1.0,
			"shutter meter reads in range")

	# --- M7: Deck B — airlock / relay / watchers / sacrifice ------------------
	_check(main._act_stage == 1, "video module aboard: no authored loss is armed")
	_check(main.hosts.size() == 1, "only the temporary probe body exists before Deck B")
	main.hosts.erase(patroller)
	patroller.queue_free()
	for _i in 4:
		await get_tree().physics_frame
	_check(main.hosts.is_empty(), "Zone 1 is threat-free before Deck B")

	_check(main.drone.MAX_TETHER <= 36.0,
			"the relay does not raise the chassis tether (%.0f m)"
			% main.drone.MAX_TETHER)

	# Reel the two-chassis test fleet, then cross on a clean sortie.
	main._try_reel(true)
	for _i in 150:
		await get_tree().physics_frame
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(main.drone != null and main.drones.size() == 1,
			"a clean Deck B sortie launches one chassis")

	# Approach the north airlock: it lifts once and stays traversable.
	main.drone.global_position = Vector3(main.ship.zone2_threshold.x, 0.32,
			main.ship.zone2_threshold.z + 1.8)
	main.drone.velocity = Vector3.ZERO
	for _i in 30:
		await get_tree().physics_frame
	_check(main.ship.zone2_door_open, "the Deck B airlock opens at the threshold")
	for _i in 180:
		await get_tree().physics_frame
	_check(main.ship.zone2_door.position.y >= main.ship.ZONE2_DOOR_OPEN_Y - 0.2,
			"the airlock panel lifts clear and stays open (y=%.2f)"
			% main.ship.zone2_door.position.y)
	_check(main.hosts.is_empty(), "the junction stays threat-free until you cross")

	# Park the Collector near the maw so the beat resolves in test time
	# without changing what triggers it.
	main.collector.global_position = main.ship.collector_sacrifice + Vector3(-2.4, 0.0, 0.0)
	main.collector.velocity = Vector3.ZERO

	# First active-drone entry wakes the hold.
	main.drone.global_position = Vector3(main.ship.zone2_threshold.x, 0.32,
			main.ship.zone2_threshold.z - 2.6)
	main.drone.velocity = Vector3.ZERO
	for _i in 20:
		await get_tree().physics_frame
	_check(main._zone2_entered, "the first crossing arms Deck B")
	_check(main.drone != null and GameState.sortie == GameState.Sortie.PILOTING,
			"crossing the threshold is not an instant kill")
	_check(main.hosts.size() == 4, "four watchers wake in the Cold Hold")
	_check(main._zone2_beat_shown and main.hud._zone_beat.text == "DECK B",
			"the zone beat is a bare deck label")
	_check(main._live_feed_active() and main.hud._live.visible,
			"live feed survives the crossing (no authored loss)")
	_check(not main.hud._end_card.visible and main._act_stage == 1,
			"no loss card and no recovery stage are forced")

	var aggressive_ok := true
	for h in main.hosts:
		aggressive_ok = aggressive_ok \
				and h.sight_range >= 20.0 and h.sight_range <= 22.0 \
				and h.sight_fov >= 100.0 and h.sight_fov <= 110.0 \
				and absf(h.move_thresh - 0.12) < 0.001 \
				and h.still_sight_range >= 4.0 and h.still_sight_range <= 6.0 \
				and absf(h.hearing_mult - 28.0) < 0.01 \
				and h.w_patrol < h.w_hunt and h.w_hunt < h.w_stalk \
				and absf(h.hunt_patience - 20.0) < 0.01
	_check(aggressive_ok, "all four watchers use the aggressive Deck B profile")

	_check(main.drone.anchor_pos.distance_to(main.ship.zone2_relay) < 0.001,
			"the active chassis tethers to the relay")
	_check(main.scanner.anchor_pos.distance_to(main.ship.zone2_relay) < 0.001
			and main.scanner.anchor_label == "RELAY",
			"the radar anchor and label follow the relay")
	_check(main.drone.flashlight_installed
			and main.drone.flashlight.spot_range > 12.0
			and main.drone.flashlight.spot_angle <= 25.0,
			"the fitted flashlight opens a narrow beam in the dark (%.1f m)"
			% main.drone.flashlight.spot_range)
	_check(main.drone.lamp.omni_range <= 3.0,
			"the emergency omni stays a close glow once the flashlight is fitted")
	for _i in 90:
		await get_tree().physics_frame
	_check(main._zone2_dark and main._env != null
			and main._env.ambient_light_energy < 0.15,
			"the hold fades to genuine darkness (%.3f)"
			% (main._env.ambient_light_energy if main._env != null else -1.0))

	# The Collector feeds itself once, on screen and through the hull.
	var sacrifice_frames := 0
	while not main._collector_sacrificed and sacrifice_frames < 900:
		await get_tree().physics_frame
		sacrifice_frames += 1
	_check(main._collector_sacrificed and main.collector.consumed,
			"the Collector is consumed on the first Deck B entry")
	_check(main.processor.dormant, "the Processor goes dormant after the meal")
	_check(main.is_ancestor_of(main.collector._lantern)
			and main.is_ancestor_of(main.collector._sack),
			"the empty lantern and sack remain on the deck")
	main._on_active_enter_zone2()
	for _i in 10:
		await get_tree().physics_frame
	_check(main.hosts.size() == 4 and main.collector.consumed,
			"re-entering does not repeat the spawn or the meal")

	# The side hall is a one-shot, and it yields the drone no matter what.
	# A watcher *inside* the hall defers the beat rather than competing; one
	# patrolling the open hold near the mouth must not suppress it (that was
	# the trigger bug).
	var defer_host = main.hosts[0]
	defer_host.drone = null
	defer_host.global_position = main.ship.crawler_grab + Vector3(0.0, 0.0, 1.0)
	main._try_start_crawler(main.ship.crawler_setpiece)
	_check(main.crawler == null, "a watcher at the crawl origin defers the crawler")
	defer_host.global_position = main.ship.crawler_setpiece + Vector3(0.0, 0.0, -2.5)
	defer_host.state = defer_host.State.PATROL
	for h in main.hosts:
		h.drone = null
		if h != defer_host:
			h.global_position = Vector3(-25.0, 0.2, -65.0)
		h.velocity = Vector3.ZERO
	main.drone.global_position = main.ship.crawler_setpiece + Vector3(0.0, 0.12, -1.5)
	main.drone.velocity = Vector3.ZERO
	for _i in 12:
		await get_tree().physics_frame
	_check(main.crawler != null and main.crawler.active,
			"the crawler arms at the side-hall entrance even with a watcher near the mouth")
	_check(main.hud._subtitle.text != "", "the crawler gets a subtitle channel")
	main.drone.global_position = main.ship.crawler_setpiece + Vector3(-11.0, 0.12, -8.0)
	main.drone.velocity = Vector3.ZERO
	for _i in 120:
		await get_tree().physics_frame
	_check(main._crawler_done and main.crawler.done,
			"leaving the hall resolves the crawler at its authored mark")
	_check(main.drone != null and GameState.sortie == GameState.Sortie.PILOTING,
			"the crawler cannot kill or soft-lock the sortie")
	var debug_line: String = main._host_debug()
	_check(debug_line.begins_with("enemies 5  zone2 hosts 4") and debug_line.contains("nearest"),
			"F3 reports the hostile roster (%s)" % debug_line)
	_check(main._nearest_host(main.drone.global_position) != null,
			"F3 can name the nearest body")

	# --- Deck C: engine room, relay and its Stalker ------------------------
	_check(main.stalker != null and is_instance_valid(main.stalker),
			"the engine room has its Stalker at boot")
	if main.stalker != null:
		_check(main.stalker.state == main.stalker.State.AMBUSH,
				"the engine Stalker opens in its lair ambush")
	main.drone.global_position = main.ship.engine_entry
	main.drone.velocity = Vector3.ZERO
	for _i in 20:
		await get_tree().physics_frame
	_check(main.drone.anchor_pos.distance_to(main.ship.engine_relay) < 0.001,
			"the engine room switches the tether to its own relay")
	_check(main.scanner.anchor_pos.distance_to(main.ship.engine_relay) < 0.001
			and main.scanner.anchor_label == "ENGINE",
			"the radar anchor and label follow the engine relay")
	_check(main._visited_zones.has("engine"),
			"Deck C inks once the drone enters the engine room")
	if main.stalker != null:
		_check(main.stalker.drone == main.drone,
				"the engine Stalker binds to the active chassis")
		main.stalker.drone = null   # deterministic map checks below

	# --- M5: hull audio bus + hand-copy map ------------------------------------
	_check(AudioServer.get_bus_index("Hull") != -1, "hull-borne audio bus exists")
	_check(main._visited_zones.has("spur"), "spur inked after the salvage run")
	_check(main._visited_zones.has("zone2") and main._visited_zones.has("crawler"),
			"Deck B inks only after the drone has been there")
	_check(main._visited_zones.has("engine"),
			"Deck C inks only after the drone has been there")
	main._open_map()
	await get_tree().physics_frame
	_check(main._map_open and main.hud._map_view.visible, "hand-copy map opens")
	_check(main.hud._map_view.data.get("stage", -1) == 1,
			"map shows the module-aboard stage (no forced recovery)")
	_check(main.hud._map_view.data.get("zone2_visited", false),
			"the map carries its own Deck B sheet")
	_check(main.hud._map_view.data.get("engine_visited", false),
			"the Deck B sheet inks the engine room")
	_check(main.hud._map_view.data.get("relay", Vector3.ZERO)
			.distance_to(main.ship.zone2_relay) < 0.001,
			"the map marks the Cold Hold relay")
	_check(main.hud._map_view.data.get("engine_relay", Vector3.ZERO)
			.distance_to(main.ship.engine_relay) < 0.001,
			"the map marks the engine relay")
	_check(main.level.map_surface != null
			and (main.level.map_surface.material_override as StandardMaterial3D).albedo_texture != null,
			"the bay map table renders the live chart")
	main._close_map()
	await get_tree().physics_frame
	_check(not main._map_open and not main.hud._map_view.visible, "map closes cleanly")

	print("AUTOTEST", " FAILED" if _failed else " PASS")
	get_tree().quit(1 if _failed else 0)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS: ", what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failed = true
	print("FAIL: ", what)
