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
	_check(main._zone_at(main.ship.PROCESSOR_PILE) == "processor",
			"the feed chamber is its own map zone")
	_check(main._zone_at(main.ship.PROCESSOR_DROP) == "processor",
			"the drop mark inks the Processor wing")

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
		_check(get_viewport().get_camera_3d() != main.drone.cam,
				"no live drone camera is current")
		_check(main.hud._lens.visible, "no live view: black lens while piloting")
		_check(not main.hud._blind.visible, "lamp veil is retired: radar is the display")
		_check(not main.hud._feed.visible, "no photo held at launch")
		_check(not main.hud._live.visible, "no live tube before the module")
		_check(main.hud._scanner.visible, "radar is visible as the primary display")
		_check((main.hud._scanner.anchor_right - main.hud._scanner.anchor_left) >= 0.7
				and (main.hud._scanner.anchor_bottom - main.hud._scanner.anchor_top) >= 0.8,
				"radar takes most of the screen")
		_check(main.SHUTTER_TIME >= 4.0,
				"still camera has a slow recharge (%.1f s)" % main.SHUTTER_TIME)
		_check(main._feed_vp != null
				and main._feed_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"still-camera viewport exists but is not rendering live")

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
		_check(absf(second.global_position.z
				- (main.ship.dock_pos.z - main.DRONE_CRADLE_GAP)) < 0.3,
				"the deployed cradle sits deeper in the ship corridor")
		_check(second_start.z < main.ship.dock_pos.z - 0.5,
				"the deployed cradle is ship-side of the sealed bay wall")
		_check(main.drone == second,
				"the link moves to the newly deployed chassis")
		_check(not lead.controlled and second.controlled,
				"exactly one chassis takes input")
		_check(main.scanner.drone == second and main.hosts[0].drone == second,
				"scanner and host bind to the deployed chassis")
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
		_check(main.scanner.echoes.size() > 0,
				"scanner collected %d wall echoes" % main.scanner.echoes.size())

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
		_check(main.hosts[0].drone == null, "hosts lose the drone's scent while you stand")
		_check(get_viewport().get_camera_3d() == main.player.cam,
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
		_check(main.level.pilot_chair.prompt == "Resume the drone",
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
		_check(get_viewport().get_camera_3d() != main.drone.cam,
				"no live drone view on resume before the module")
		_check(main.scanner.drone == main.drone and main.hosts[0].drone == main.drone,
				"scanner + hosts reacquire the drone on resume")
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
	_check(get_viewport().get_camera_3d() == main.player.cam, "player camera restored")

	# Second sortie: tether clamp + the battery-forced reel path.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(GameState.sortie == GameState.Sortie.PILOTING, "second sortie launches clean")
	if main.drone != null:
		main.drone.global_position = main.ship.dock_pos + Vector3(0, 0, -60.0)
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

	# --- M2: hosts / objective / door / caught / deliver ----------------------
	_check(main.hosts.size() == 1, "one ordinary host resident in the ship")

	# Wandering regression: the patroller must walk its loop, not stand at the
	# end of a hall. (Bug history: waypoints crossed the junction wall, so
	# straight-line seek wedged and the arrival check never advanced the loop.)
	main._knock_t = 9999.0   # silence ambient lures during the measurement
	var patrol_walk = main.hosts[0]
	patrol_walk.global_position = Vector3(-2.4, 0.2, -10.0)
	patrol_walk.reset()
	var traveled := 0.0
	var last_p: Vector3 = patrol_walk.global_position
	var wp0: int = patrol_walk._wp
	for _i in 480:
		await get_tree().physics_frame
		if _i % 60 == 0:
			traveled += patrol_walk.global_position.distance_to(last_p)
			last_p = patrol_walk.global_position
	traveled += patrol_walk.global_position.distance_to(last_p)
	_check(traveled > 3.0, "patroller wanders the halls (%.1f m in 8 s)" % traveled)
	_check(patrol_walk._wp != wp0, "patroller cycles its waypoint loop")

	# Hearing model: one quiet noise makes the host CURIOUS. It must listen,
	# not walk to the sound. This is the main leeway change.
	var patroller = main.hosts[0]
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
	# other hosts. Player/drone/environment noise stays audible. The ship now
	# carries one ordinary host, so the probe spawns a temporary second body.
	var h0 = main.hosts[0]
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
				"the galley is empty behind the opened door (no resident)")

		# Organic seam-cross drive: doorway -> big galley -> cold room, zero
		# teleports. Hosts detached (test-only) so the run measures geometry.
		for h in main.hosts:
			h.drone = null
		# Stage 1: west across the hall, stop east of the pantry wall line.
		main.drone.rotation.y = PI * 0.5          # face -X
		main.drone.velocity = Vector3.ZERO
		Input.action_press("move_forward")
		for _i in 600:
			await get_tree().physics_frame
			if main.drone.global_position.x <= -16.5:
				Input.action_release("move_forward")
				main.drone.velocity.x = 0.0
				break
		for _i in 10:
			await get_tree().physics_frame
		# Stage 2: NORTH to the pantry-mouth band (brake at the line).
		main.drone.rotation.y = 0.0                # face -Z
		for _i in 200:
			Input.action_press("move_forward")
			await get_tree().physics_frame
			if main.drone.global_position.z <= -32.6:
				Input.action_release("move_forward")
				main.drone.velocity.z = 0.0
				break
		for _i in 10:
			await get_tree().physics_frame
		# Stage 3: WEST into the cold room mouth (pickup fires at the door).
		main.drone.rotation.y = PI * 0.5
		Input.action_press("move_forward")
		for _i in 140:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for h in main.hosts:
			h.drone = main.drone
			h.state = h.State.PATROL
		_check(main._cargo == "rations",
				"drove through door + galley + alcove seams and secured the rations (x=%.1f z=%.1f)"
				% [main.drone.global_position.x, main.drone.global_position.z])

		# Cargo belongs to the chassis, not the link: hop to the empty bot and
		# back, and the ration pack is still on the one that picked it up.
		var cargo_bot = main.drone
		main._cycle_drone()
		for _i in 20:
			await get_tree().physics_frame
		_check(main.drone != cargo_bot and main._cargo == "",
				"the empty chassis does not inherit the other bot's cargo")
		main._cycle_drone()
		for _i in 20:
			await get_tree().physics_frame
		_check(main.drone == cargo_bot and main._cargo == "rations",
				"cargo persists on the chassis across the link transfer")

		# Loss: a stalking host at contact kills the module drone, rejects cargo.
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
	# Recall the survivor so the delivery run starts from a clean fleet.
	main._try_reel(true)
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "reeling the last chassis ends the sortie")

	# Deliver: pick up again, then reel home -> meters rise, objective done.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	var kcal_before: float = GameState.kcal
	# Deterministic delivery phase: park the patroller at the spur end and pin
	# it to PATROL (the run measures the delivery path, not hunt pacing).
	for h in main.hosts:
		h.state = h.State.PATROL
	main.hosts[0].global_position = Vector3(8.0, 0.2, -29.2)
	main.drone.global_position = Vector3(-17.6, 0.32, -32.7)
	main.drone.velocity = Vector3.ZERO
	for _i in 20:
		await get_tree().physics_frame
	_check(main._cargo == "rations", "objective recovered on retry")
	main.drone.global_position = main.ship.dock_pos
	main.drone.velocity = Vector3.ZERO
	for _i in 60:   # let the launch grace expire (battery-based guard)
		await get_tree().physics_frame
	main._try_reel(false)   # deliberate reel near the dock
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "delivery reel teardown")
	_check(GameState.kcal > kcal_before, "rations delivered: kcal %.2f > %.2f" % [GameState.kcal, kcal_before])
	_check(main._objective_state == "none", "objective complete after delivery")

	# --- M3: video module salvage -> deliver -> install -> stills ------------
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	if main.drone != null:
		for h in main.hosts:
			h.drone = null   # deterministic checks; no pursuits for this leg
		main.drone.global_position = Vector3(6.3, 0.32, -29.2)
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

	# The next sortie now has LIVE video: the drone camera is the main view,
	# the black lens is gone, and the radar becomes a compact inset.
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(main._live_feed_active(), "installed module unlocks the live feed")
	_check(main.drone.live_view, "live camera handoff is armed")
	_check(get_viewport().get_camera_3d() == main.drone.cam,
			"live drone view is the current camera")
	_check(not main.hud._lens.visible, "live feed: no black lens")
	_check(main.hud._live.visible, "live tube filter is shown")
	_check(not main.hud._feed.visible, "live feed: no held print")
	_check(not main.hud._blind.visible, "live feed: no lamp veil")
	_check(main.hud._shutter.visible, "shutter meter still shown")
	_check(main.hud._scanner.visible, "radar stays available as an inset")
	_check(absf(main.hud._scanner.anchor_left - 0.72) < 0.01,
			"radar shrinks to the live-feed corner")
	main.hud.set_live_stress(0.75, -0.5)
	_check(absf(float(main.hud._live_mat.get_shader_parameter("stress")) - 0.75) < 0.01,
			"live tube takes drive stress")
	_check(absf(float(main.hud._live_mat.get_shader_parameter("turn")) + 0.5) < 0.01,
			"live tube takes signed steering")
	main.hud.set_live_stress(0.0, 0.0)
	# Deploy the second chassis so the authored interception leaves a survivor.
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
	_check(main.hud._feed.visible, "the print is displayed over the live feed")
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
	_check(not main.hud._lens.visible, "live view returns with no black lens")
	_check(main.hud._shutter_frac >= 0.0 and main.hud._shutter_frac <= 1.0,
			"shutter meter reads in range")

	# --- M4: the primary stalker is a late, persistent third body ------------
	_check(main._act_stage == 1, "video module aboard arms the interception")
	# It must not spawn while the drone is still in the initial hallway.
	main.drone.global_position = Vector3(0.4, 0.32, -21.0)
	main.drone.velocity = Vector3.ZERO
	for _i in 30:
		await get_tree().physics_frame
	_check(not main._stalk_triggered, "stalker stays out of the initial hallway")
	_check(main._m4_host == null, "no stalker before the first room")

	# The first room is the junction: entering it wakes the beat.
	main.drone.global_position = Vector3(0.4, 0.32, -27.0)
	main.drone.velocity = Vector3.ZERO
	for _i in 20:
		await get_tree().physics_frame
	_check(main._stalk_triggered, "stalker spawns in the first room")
	var loss_pos: Vector3 = main.drone.global_position
	var stalker = main._m4_host
	_check(stalker != null, "stalker exists")
	if stalker != null:
		_check(stalker.state == stalker.State.PATROL, "stalker spawns on patrol")
		_check(stalker.waypoints.size() >= 6, "stalker has a hall patrol route")
		_check(stalker.global_position.distance_to(main.drone.global_position) > 8.0,
				"stalker spawns far away (%.1f m)" % stalker.global_position.distance_to(main.drone.global_position))
		_check(stalker._rig != null and stalker._head != null and stalker._arm_l != null
				and stalker._leg_l != null, "stalker has a modelled body")
		_check(not stalker.radar_blips,
				"stalker is a radar mass, not a blip source")
		_check(main.scanner.masses.size() == 1, "radar carries the stalker as a mass")
		_check(main._m4_light != null and main._m4_light.shadow_enabled,
				"event lamp lights the junction")
		var blips_before: int = main.scanner.blips.size()
		main.scanner._on_noise(stalker.global_position, 0.9, stalker)
		_check(main.scanner.blips.size() == blips_before,
				"stalker makes no radar blips")

		# Proximity poisoning: the feed collapses and the hum rises as it closes.
		_check(stalker._hum != null, "stalker carries a proximity hum")
		stalker.set_physics_process(false)
		stalker.global_position = main.drone.global_position + Vector3(0, -0.12, -1.0)
		stalker._animate(0.016)
		var hum_near: float = stalker._hum.volume_db
		for _i in 2:
			await get_tree().physics_frame
		_check(main.hud._live_dread > 0.6, "close stalker poisons the live feed")
		_check(float(main.hud._live_mat.get_shader_parameter("dread")) > 0.6,
				"live shader receives the proximity poison")
		stalker.global_position = main.drone.global_position + Vector3(0, 0, 8.0)
		stalker._animate(0.016)
		var hum_far: float = stalker._hum.volume_db
		for _i in 2:
			await get_tree().physics_frame
		_check(hum_near > hum_far + 5.0,
				"hum grows louder as the stalker closes (%.1f -> %.1f dB)" % [
					hum_far, hum_near])
		_check(main.hud._live_dread < 0.2, "feed clears when the stalker is far")

		# Low tables are true cover: a drone under one is not visible.
		main.drone.global_position = Vector3(0.0, 0.32, -31.2)
		await get_tree().physics_frame
		_check(not stalker._can_see_drone(), "low table hides the drone from sight")
		main.drone.global_position = loss_pos
		stalker.set_physics_process(true)

	# The stalker closes and takes it (deterministic contact for the test).
	if stalker != null:
		stalker.global_position = loss_pos + Vector3(0.35, -0.12, 0.35)
		stalker.force_chase()
	for _i in 160:
		await get_tree().physics_frame
	_check(main.drone != null, "a surviving chassis carries the run after the module drone dies")
	_check(main.drones.size() == 1, "the module chassis is struck from the fleet")
	_check(not main._camera_installed, "video module goes with the drone")
	_check(main._act_stage == 2, "act flips to module recovery")
	_check(main.hud._end_card.visible, "the loss card is shown")
	_check(main._camera_site_pos.distance_to(loss_pos) < 2.0,
			"the wreck site records where the drone fell")
	_check(main._m4_host != null, "the stalker persists after the kill")
	_check(main._m4_light != null, "the event lamp remains in the junction")
	_check(main.hosts.size() == 2, "the patroller plus the stalker remain")
	_check(main.scanner.masses.size() == 1, "the radar mass persists with the stalker")
	if stalker != null:
		var settle := 0
		while stalker.state != stalker.State.PATROL and settle < 900:
			await get_tree().physics_frame
			settle += 1
		_check(stalker.state == stalker.State.PATROL,
				"the stalker returns to patrol after the kill")
	var blocking := false
	for piece in main.ship.wreck_pieces:
		if piece.use_collision:
			blocking = true
	_check(main.ship.wreck_pieces.size() == 2 and not blocking,
			"the loss wreck is visual-only and cannot block a lane")
	main.hud.hide_end_card()

	# Recovery sortie: recall the survivor, then launch a clean fleet. Losing
	# the module takes the live feed with it.
	main._try_reel(true)
	for _i in 150:
		await get_tree().physics_frame
	_check(main.drone == null, "the surviving chassis is recalled for the recovery run")
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(not main._live_feed_active(), "module loss takes the live feed away")
	_check(not main.drone.live_view, "recovery drone is camera-handoff off")
	_check(get_viewport().get_camera_3d() != main.drone.cam,
			"recovery sortie is back on the player camera")
	_check(not main.hud._feed.visible, "recovery sortie starts with no photo held")
	_check(main.hud._lens.visible, "black lens returns while the module is lost")
	_check(not main.hud._live.visible, "live tube is gone with the module")
	if main.drone != null:
		for h in main.hosts:
			h.drone = null
		main.drone.global_position = main._camera_site_pos + Vector3(0.3, 0.0, 0.2)
		main.drone.velocity = Vector3.ZERO
		for _i in 20:
			await get_tree().physics_frame
		_check(main._cargo == "camera", "video module recovered from the wreck")
		main.drone.global_position = main.ship.dock_pos
		main.drone.velocity = Vector3.ZERO
		for h in main.hosts:
			h.drone = main.drone
		for _i in 60:
			await get_tree().physics_frame
		main._try_reel(false)
	for _i in 150:
		await get_tree().physics_frame
	_check(main._camera_held, "recovered video module delivered to the bay")
	main._at_fabricator()
	await get_tree().physics_frame
	_check(main._camera_installed, "video module reinstalled after recovery")
	_check(main._act_stage == 3, "free sorties after recovery")
	main._start_sortie()
	for _i in 6:
		await get_tree().physics_frame
	_check(main._live_feed_active(), "reinstall restores the live feed")
	_check(get_viewport().get_camera_3d() == main.drone.cam,
			"refitted drone is flying on the live camera")
	_check(not main.hud._lens.visible, "live feed is back after refit")
	_check(main.hud._live.visible, "live tube is back after refit")
	var photos_before: int = main._photo_count
	main._take_photo()
	for _i in 3:
		await get_tree().physics_frame
	_check(main._photo_count == photos_before + 1, "the still optic works after reinstall")
	_check(main.hud._feed.visible, "the still camera still works after the refit")

	# --- M5: hull audio bus + hand-copy map ------------------------------------
	_check(AudioServer.get_bus_index("Hull") != -1, "hull-borne audio bus exists")
	_check(main._visited_zones.has("galley"), "galley inked after the food run")
	_check(main._visited_zones.has("spur"), "spur inked after the salvage run")
	main._open_map()
	await get_tree().physics_frame
	_check(main._map_open and main.hud._map_view.visible, "hand-copy map opens")
	_check(main.hud._map_view.data.get("stage", -1) == 3, "map shows the recovery stage")
	_check(main._charted.size() > 20,
			"radar swept %d wall cells into the map" % main._charted.size())
	var charted_draw: Array = main.hud._map_view.data.get("charted", [])
	_check(charted_draw.size() > 20, "map data carries the charted points (%d)" % charted_draw.size())
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
