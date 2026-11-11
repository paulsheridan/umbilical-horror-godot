extends Node3D
## UMBILICAL M4+M5 orchestration.
##
## M4 (the authored loss): the first sortie with real eyes ends in loss.
## The interception is diegetic — a lure walks the patroller down the sound
## of your machine until contact, never a cutscene. The wreck lands at the
## spot it fell, the objective flips to blind recovery, and the module waits
## in the wreck until you go back for it. Loss is the tutorial, not the end.
##
## M5 (polish): hull-borne sound routing (see sfx.gd), motor load pitch,
## feed jitter, and the hand-copy map — compartments only ink in once a
## drone has actually been there; the wreck site is a marked place.
##
## M6b: the drone fleet. Chassis deploy one at a time at the dock and stay
## where they are left; `drone` is the linked one and `drones` holds the rest.
## Only the linked bot drains and steers; B deploys, Q / 1-2 move the link; a
## lost chassis is struck from the fleet and the link hops to a survivor.

const FAB_BAY := preload("res://src/hub/fab_bay.gd")
const BEYOND := preload("res://src/ship/beyond.gd")
const DRONE := preload("res://src/drone/drone.gd")
const SCANNER := preload("res://src/ui/scanner.gd")
const HOST := preload("res://src/host/host.gd")
const STALKER := preload("res://src/host/stalker.gd")
const COLLECTOR := preload("res://src/host/collector.gd")
const PROCESSOR := preload("res://src/host/processor.gd")

var level
var ship
var player: CharacterBody3D
## The fleet. `drone` is always the bot the player is currently flying; the
## rest sit parked where they were left, keeping position, heading, charge and
## cargo. Switching moves the link, not the ships. Bots deploy one at a time.
var drones: Array = []
var drone = null
var _drone_index := 0
const DRONE_FLEET := 2          # max chassis alive at once
const DRONE_CRADLE_GAP := 1.5
var _swap_cd := 0.0
var _deploy_cd := 0.0
var hud: CanvasLayer
var scanner: Control
var hosts: Array = []
var collector = null            # the Collector: a scavenger, not a hunter
var processor = null            # the Processor: a pinned mouth, not a hunter

var _started := false
var _paused := false
var _knock_t := 26.0
var _meters_t := 0.0
var _static_boost := 0.0
var _static_lock := 0.0
var _reeling := false
var _dock_prompt := false

# Objective / cargo state. One cargo slot (the drone is small).
var _objective_state := "pending"   # rations chain (HUD bookkeeping)
var _cargo := ""                    # "", "rations", "camera"
var _camera_held := false
var _camera_installed := false

# Act structure (M4): 0 module not yet found / 1 module aboard, interception
# live / 2 module recovery / 3 free sorties after recovery.
var _act_stage := 0
var _camera_site_pos := Vector3.ZERO
var _stalk_triggered := false
var _m4_host = null            # the primary stalker, spawned on the M4 beat
var _m4_light: OmniLight3D = null   # cold event lamp over the junction
var _pending_end_card := false

# M5 map.
var _map_open := false
var _visited_zones := {"bay": true}
var _cafeteria_seen := false
# Radar-charted walls: persistent world-grid of scanner returns, shown as ink
# on the hand-copy map. The sweep literally fills the map in.
const CHART_GRID := 0.5
const CHART_CAP := 900
var _charted := {}          # "gx:gz" -> true
var _charted_pts: Array = []  # Vector3 per charted cell (parallel, for draw)

# The primary bad guy's default route: the annex donut, from the far north
# ring to the cafeteria and back to the junction mouth. It deliberately
# avoids the low tables in the junction and cafeteria.
const STALKER_PATROL := [
	Vector3(12.0, 0.0, -29.7),    # far spawn, north ring
	Vector3(18.6, 0.0, -29.7),    # north ring east
	Vector3(20.1, 0.0, -25.0),    # east ring
	Vector3(20.1, 0.0, -18.5),    # east ring south
	Vector3(17.0, 0.0, -16.8),    # south ring east
	Vector3(12.0, 0.0, -16.8),    # south ring
	Vector3(9.0, 0.0, -18.5),     # cafeteria south
	Vector3(7.0, 0.0, -22.0),     # cafeteria west arch
	Vector3(5.4, 0.0, -26.0),     # west ring north
	Vector3(5.4, 0.0, -29.6),     # spur mouth / junction approach
]

# The Collector's walking loop. It stays east of the junction: the start of
# the game (bay, corridor, junction) is deliberately left to the patroller
# alone. The loop circles the annex donut, dips into the berth wing, and now
# runs out along the Processor hall to the feeding pile and back. Remains are
# scattered along this path (ship._berth_wing).
const COLLECTOR_ROUTE := [
	Vector3(19.8, 0.0, -7.2),     # ossuary / home
	Vector3(19.8, 0.0, -11.2),    # nest door
	Vector3(17.7, 0.0, -11.7),    # berth hall
	Vector3(21.6, 0.0, -11.7),    # Processor hall mouth
	Vector3(24.6, 0.0, -11.7),    # Processor hall
	Vector3(27.6, 0.0, -11.7),    # hall end
	Vector3(29.8, 0.0, -11.7),    # the pile: feed the Processor
	Vector3(27.6, 0.0, -11.7),    # back down the hall
	Vector3(24.6, 0.0, -11.7),
	Vector3(20.2, 0.0, -11.7),    # berth hall
	Vector3(17.7, 0.0, -11.7),    # line up with the east link
	Vector3(17.6, 0.0, -14.5),    # east link
	Vector3(18.4, 0.0, -16.8),    # south ring east
	Vector3(14.0, 0.0, -16.8),    # south ring
	Vector3(9.0, 0.0, -16.8),     # south ring west
	Vector3(6.0, 0.0, -17.0),     # SW corner
	Vector3(5.4, 0.0, -20.0),     # west ring
	Vector3(5.4, 0.0, -23.0),     # west ring
	Vector3(5.4, 0.0, -26.0),     # west ring north
	Vector3(5.4, 0.0, -29.6),     # west ring / north ring corner
	Vector3(9.0, 0.0, -29.6),     # north ring
	Vector3(15.0, 0.0, -29.6),    # north ring
	Vector3(19.5, 0.0, -29.7),    # north ring east
	Vector3(20.1, 0.0, -28.0),    # NE corner
	Vector3(20.1, 0.0, -24.0),    # east ring
	Vector3(20.1, 0.0, -19.0),    # east ring south
	Vector3(19.0, 0.0, -16.8),    # SE corner
	Vector3(18.4, 0.0, -16.8),    # south ring east
	Vector3(17.6, 0.0, -16.8),    # back to the east link mouth
	Vector3(17.6, 0.0, -14.5),    # east link
	Vector3(17.7, 0.0, -11.7),    # berth hall
	Vector3(19.8, 0.0, -11.2),    # nest door
]

# --- Optics: stills first, live video after the salvage ---------------------
# Every drone starts with the still camera only. Recovering the video module
# and racking it at the fabricator unlocks the live drone feed for later
# sorties; losing the module takes the feed away again until it is recovered.
const VIDEO_FEED_ENABLED := true   # master gate; actual feed also needs _camera_installed

# The photo camera is standard equipment on every first-iteration drone: a
# SubViewport that renders exactly one frame per exposure (UPDATE_ONCE).
var _feed_vp: SubViewport = null
var _feed_cam: Camera3D = null
const SHUTTER_TIME := 5.0      # slow recharge between single photographs
const PHOTO_SHOW_TIME := 2.2   # the still holds on screen this long
var _photo_cd := 0.0
var _photo_show := 0.0
var _photo_count := 0
var _no_optics_cd := 0.0
var _objective_cached := "___"

# The physical map on the table: same drawing as the overlay, rendered into a
# small SubViewport and textured onto the paper quad.
var _table_map: Control = null
var _table_t := 0.0


func _ready() -> void:
	_build_environment()

	level = FAB_BAY.new()
	add_child(level)
	level.build()
	level.pilot_chair.on_interact = Callable(self, "_start_sortie")
	level.fabricator.on_interact = Callable(self, "_at_fabricator")

	ship = BEYOND.new()
	add_child(ship)
	ship.build()
	_camera_site_pos = ship.CAMERA_POS

	_setup_table_map()

	_spawn_hosts()
	_spawn_collector()
	_spawn_processor()

	hud = CanvasLayer.new()
	hud.set_script(load("res://src/ui/hud.gd"))
	add_child(hud)
	hud.start_clicked.connect(_on_start_clicked)
	hud.resume_clicked.connect(_on_resume_clicked)

	# The still camera exists from the first launch; there is no install gate.
	_setup_feed()

	player = CharacterBody3D.new()
	player.set_script(load("res://src/player/player.gd"))
	add_child(player)
	player.position = level.player_start
	player.rotation.y = PI * 0.5
	player.focus_changed.connect(hud.set_prompt)
	player.interact_pressed.connect(_on_interact_pressed)
	player.leave_requested.connect(_leave_chair)

	scanner = SCANNER.new()
	scanner.drone = null
	scanner.anchor_pos = ship.dock_pos
	scanner.echo_recorded.connect(_on_wall_charted)
	hud.add_scanner(scanner)

	_refresh_objective_text()
	_refresh_chair_prompt()
	hud.set_meters(GameState.o2, GameState.h2o, GameState.kcal, GameState.clock_hours)
	GameState.meters_changed.connect(_refresh_meters)


func _process(delta: float) -> void:
	if not _started or _paused:
		hud.set_static_amount(0.0)
		return

	_knock_t -= delta
	if _knock_t <= 0.0:
		_hull_knock()
		_knock_t = randf_range(42.0, 95.0)

	_swap_cd = maxf(_swap_cd - delta, 0.0)
	_deploy_cd = maxf(_deploy_cd - delta, 0.0)
	_refresh_objective_text()

	# The table map fills itself in: refresh the physical paper's ink ~1.2 Hz.
	if _table_map != null:
		_table_t -= delta
		if _table_t <= 0.0:
			_table_t = 0.8
			_table_map.data = _map_data()
			_table_map.queue_redraw()

	_meters_t -= delta
	if _meters_t <= 0.0:
		_meters_t = 0.5
		hud.set_meters(GameState.o2, GameState.h2o, GameState.kcal, GameState.clock_hours)
	hud.debug_tick(delta, Engine.get_frames_per_second(), player.global_position, NoiseBus.count,
			_host_debug())

	# Objective chatter while piloting.
	var amt := 0.0
	if GameState.sortie == GameState.Sortie.PILOTING and drone != null:
		var dpos: Vector3 = drone.global_position
		var dist: float = dpos.distance_to(ship.dock_pos)
		var bars := _signal_bars(dist)
		var base: float = 0.03 + pow(1.0 - bars / 5.0, 1.5) * 0.5
		if bars <= 2 and randf() < delta * 0.5:
			_static_boost = maxf(_static_boost, 0.45)
		hud.set_drone_status(dist, drone.MAX_TETHER, bars, drone.battery)
		hud.set_fleet_line(_fleet_line())
		if _m4_host != null and is_instance_valid(_m4_host):
			_m4_host.feed_active = _live_feed_active()

		# Live-tube stress: the picture tears and ghosts with the chassis.
		if _live_feed_active():
			var planar := Vector2(drone.velocity.x, drone.velocity.z).length()
			var speed_n := clampf(planar / DRONE.HURRY_SPEED, 0.0, 1.0)
			var steer := Input.get_axis("move_left", "move_right")
			hud.set_live_stress(maxf(speed_n, absf(steer) * 0.35), -steer)
			# The primary stalker poisons the feed as it closes: first grain
			# and tears, then a rolling wash that eats the picture entirely.
			var dread := 0.0
			if _m4_host != null and is_instance_valid(_m4_host):
				var md: float = drone.global_position.distance_to(_m4_host.global_position)
				dread = pow(clampf(1.0 - md / 9.0, 0.0, 1.0), 1.4)
				# When it commits to the lunge, let the body through: the
				# scare needs a shape, not a whiteout.
				if _m4_host.state == _m4_host.State.LUNGE:
					dread = minf(dread, 0.30)
			hud.set_live_dread(dread)

		# Reel prompt appears only when the winch can actually take it.
		var near_dock := dist < 6.0
		if near_dock != _dock_prompt:
			_dock_prompt = near_dock
			hud.set_prompt("[R] reel the fleet home" if near_dock else "")

		# The map inks itself with travel: only places the drone has been.
		var zone: String = _zone_at(dpos)
		_visited_zones[zone] = true
		if zone == "cafeteria" and not _cafeteria_seen:
			_cafeteria_seen = true
		# Cabin doors are loud: they open for the drone and announce it.
		ship.service_doors(dpos, delta)

		# Pickups: one cargo slot per chassis. A second bot cannot duplicate a
		# unique objective item while the first is already carrying it.
		if _cargo == "":
			if not _camera_installed and not _camera_held \
					and not _fleet_has("camera") \
					and dpos.distance_to(_camera_site_pos) < 1.2:
				_cargo = "camera"
				drone.cargo = _cargo
				ship.camera_module.visible = false
				_hud_pickup_message()
			elif _objective_state == "pending" and not _fleet_has("rations") \
					and dpos.distance_to(ship.FOOD_POS) < 1.7:
				_cargo = "rations"
				drone.cargo = _cargo
				_hud_pickup_message()

		# The galley door: grind it open when close. Loud and witnessed. Once
		# open it stays open; the room is a shortcut to the cold store now.
		if not ship.galley_door_open and dpos.distance_to(ship.GALLEY_DOOR_POS) < 2.4:
			ship.open_galley_door()

		# M4: the primary bad guy wakes once the drone leaves the initial
		# hallway and enters the junction. It spawns far away and then runs its
		# own patrol / investigate / chase AI; there is no scripted lure.
		if _act_stage == 1 and not _stalk_triggered and _zone_at(dpos) == "junction":
			_stalk_triggered = true
			_spawn_m4_stalker()
			_static_lock = 1.1
		amt = minf(base + _static_boost + _static_lock, 1.0)
	if _m4_host != null and is_instance_valid(_m4_host) \
			and _m4_host.state == _m4_host.State.LUNGE:
		amt = minf(amt, 0.35)   # keep the rushing body readable through the snow
	_static_boost = maxf(_static_boost - delta * 0.9, 0.0)
	_static_lock = maxf(_static_lock - delta * 1.3, 0.0)
	hud.set_static_amount(amt)

	# Still camera: slow shutter recharge + photo display timing. Available on
	# every first-iteration drone; there is no optics install gate any more.
	_no_optics_cd = maxf(_no_optics_cd - delta, 0.0)
	if GameState.sortie == GameState.Sortie.PILOTING:
		_photo_cd = maxf(_photo_cd - delta, 0.0)
		if _photo_show > 0.0:
			_photo_show -= delta
			if _photo_show <= 0.0:
				hud.hide_photo()
		hud.set_shutter(1.0 - _photo_cd / SHUTTER_TIME)
	else:
		_photo_show = 0.0

	if _map_open:
		hud.show_map(_map_data())


func _input(event: InputEvent) -> void:
	if not _started:
		return
	# The hand-copy map has its own input grammar: E/ESC/click closes.
	if _map_open:
		if event.is_action_pressed("pause") \
				or (event.is_action_pressed("interact") and not event.is_echo()) \
				or (event is InputEventMouseButton and event.pressed
					and event.button_index == MOUSE_BUTTON_LEFT):
			_close_map()
		return
	var lmb: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	# Also read the raw F key: project input maps can be stale in a running
	# editor session, and the shutter must never depend on that.
	var fkey: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_F or event.keycode == KEY_F)
	# Raw R fallback, same reasoning as F: the input map can be stale inside a
	# running editor session, and the winch must never depend on that.
	var rkey: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_R or event.keycode == KEY_R)
	# Fleet link keys: Q cycles, 1..N selects directly. Raw fallbacks for the
	# same stale-input-map reason as F/R.
	var qkey: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_Q or event.keycode == KEY_Q)
	var bkey: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_B or event.keycode == KEY_B)
	if GameState.sortie == GameState.Sortie.PILOTING and not _paused \
			and ((event.is_action_pressed("swap_drone") and not event.is_echo()) or qkey):
		_cycle_drone()
	if GameState.sortie == GameState.Sortie.PILOTING and not _paused \
			and ((event.is_action_pressed("deploy_drone") and not event.is_echo()) or bkey):
		_deploy_drone()
	if GameState.sortie == GameState.Sortie.PILOTING and not _paused \
			and event is InputEventKey and event.pressed and not event.echo:
		for i in drones.size():
			var code: int = KEY_1 + i
			if event.keycode == code or event.physical_keycode == code:
				_switch_drone(i)
	if GameState.sortie == GameState.Sortie.PILOTING and not _paused \
			and ((event.is_action_pressed("reel") and not event.is_echo()) or rkey):
		_try_reel(false)
	if GameState.sortie == GameState.Sortie.PILOTING and not _paused \
			and (event.is_action_pressed("photo") or fkey or lmb):
		_take_photo()
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif lmb and not _paused:
		# Re-assert capture on click — some window managers silently drop it.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## The still camera: one frame per exposure, then a slow mechanical recharge.
## Standard on every drone, and still available once the live feed is online.
func _take_photo() -> void:
	if GameState.sortie != GameState.Sortie.PILOTING or drone == null:
		return
	if _feed_vp == null:
		_setup_feed()
	if _feed_cam == null:
		return
	if _reeling or _photo_cd > 0.0:
		return
	_photo_cd = SHUTTER_TIME
	_photo_show = PHOTO_SHOW_TIME
	_photo_count += 1
	_feed_cam.global_transform = drone.cam.global_transform
	# UPDATE_ONCE: exactly one render per photograph. Live video stays off.
	_feed_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	hud.set_feed_source(_feed_vp)
	hud.show_photo()
	Sfx.play("shutter", Sfx.CENTER, -8.0)
	hud.set_shutter(0.0)


# --------------------------------------------------------------------------
# Boot / pause / wiring
# --------------------------------------------------------------------------

func _on_start_clicked() -> void:
	if _started:
		return
	_started = true
	GameState.running = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.begin_game()


func _on_resume_clicked() -> void:
	if _paused:
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	GameState.paused = _paused
	hud.set_paused_ui(_paused)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED)


func _on_interact_pressed() -> void:
	if _map_open:
		_close_map()
		return
	# E in the chair is routed through leave_requested; an interact event that
	# somehow arrives while piloting is a no-op, never a reel.
	if GameState.sortie == GameState.Sortie.PILOTING:
		return
	if player.focus == level.map_table:
		_open_map()
	else:
		player._on_interact_pressed()


# --------------------------------------------------------------------------
# The hand-copy map (M5)
# --------------------------------------------------------------------------

func _open_map() -> void:
	_map_open = true
	GameState.map_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Sfx.play("tick", Sfx.CENTER, -10.0)
	hud.show_map(_map_data())


func _close_map() -> void:
	_map_open = false
	GameState.map_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Sfx.play("tick", Sfx.CENTER, -12.0)
	hud.hide_map()


func _map_data() -> Dictionary:
	return {
		"stage": _act_stage,
		"site": _camera_site_pos,
		"dock": ship.dock_pos,
		"door_open": ship.galley_door_open,
		"rations_pending": _objective_state == "pending",
		"camera_installed": _camera_installed,
		"visited": _visited_zones,
		"charted": _charted_pts,
	}


## Radar returns become permanent map knowledge: 0.5 m-gridded, deduped, and
## capped. A swept wall also counts as having "been there" for the map.
func _on_wall_charted(pos: Vector3) -> void:
	if _charted.size() >= CHART_CAP:
		return
	var gx := int(round(pos.x / CHART_GRID))
	var gz := int(round(pos.z / CHART_GRID))
	var key := "%d:%d" % [gx, gz]
	if _charted.has(key):
		return
	_charted[key] = true
	_charted_pts.append(Vector3(gx * CHART_GRID, 0.0, gz * CHART_GRID))
	_visited_zones[_zone_at(pos)] = true


## True when any chassis in the fleet (active mirror included) already carries
## this unique objective item. Prevents a second bot duplicating the module or
## the ration pack.
func _fleet_has(kind: String) -> bool:
	if _cargo == kind:
		return true
	for d in drones:
		if d != drone and d.cargo == kind:
			return true
	return false


## Render the hand-copy map onto the physical table paper (live radar ink).
## The bay is the one room that shows your knowledge without an overlay.
func _setup_table_map() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_table_map = (load("res://src/ui/map_view.gd") as GDScript).new()
	_table_map.size = Vector2(512, 256)
	_table_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_map.fit_to(512, 256)
	vp.add_child(_table_map)
	add_child(vp)
	var mat := level.map_surface.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_texture = vp.get_texture()
	_table_map.data = _map_data()
	_table_map.queue_redraw()


## F3 diagnostics: where the patroller is and what it's doing, live.
func _host_debug() -> String:
	if hosts.is_empty():
		return ""
	var h = hosts[0]
	var state_name: String = ["PATROL", "CURIOUS", "HUNT", "STALK"][int(h.state)]
	return "host: %s wp %d  pos (%.1f, %.1f)  v %.2f  stuck-run %d" % [
		state_name, h._wp, h.global_position.x, h.global_position.z,
		Vector2(h.velocity.x, h.velocity.z).length(), h._stuck_run,
	]


func _zone_at(p: Vector3) -> String:
	if p.x < -17.2 and p.z < -31.4:
		return "coldroom"
	if p.x < -8.4 and p.z < -24.0:
		return "galley"
	# Processor wing: the long east hall and its feed chamber.
	if p.x > 21.2 and p.z > -15.6 and p.z < -7.8:
		return "processor"
	# Berth wing: the crew's rooms south of the annex ring.
	if p.x > 7.0 and p.z > -16.0 and p.z < -5.6:
		return "berths"
	# East annex. The old spur is the western end of the north ring; keep it
	# as its own map zone so the salvage site still inks separately.
	if p.x > 4.6 and p.z < -16.0 and p.z > -31.6:
		if p.x > 6.2 and p.x < 19.2 and p.z > -28.4 and p.z < -17.6:
			return "cafeteria"
		if p.x < 9.0 and p.z < -28.4:
			return "spur"
		return "annex"
	if p.z < -25.6:
		return "junction"
	if p.z < -14.0 and p.z > -16.6:
		return "bend"
	if p.z < -5.4:
		return "corridor"
	return "bay"


# --------------------------------------------------------------------------
# Objective banner
# --------------------------------------------------------------------------

func _refresh_objective_text() -> void:
	var t := ""
	if _cargo == "rations":
		t = "OBJECTIVE: bring the rations home"
	elif _cargo == "camera":
		t = "OBJECTIVE: video module — bring it home to the dock"
	elif not _camera_installed:
		if _camera_held:
			t = "OBJECTIVE: install the video module — fabricator (E)"
		elif _act_stage == 2:
			t = "OBJECTIVE: RECOVER the video module — out at the wreck site"
		elif _act_stage == 0 and _objective_state == "pending":
			t = "OBJECTIVE: RATIONS — the cold room, past the galley door\nALSO: video module (live-feed upgrade) — east-spur wreck, past the junction"
		else:
			t = "OBJECTIVE: SALVAGE — a video camera module in the east-spur wreck"
	elif _act_stage == 1:
		t = "OBJECTIVE: video module aboard — live feed armed, fly a sortie"
	elif _objective_state == "pending":
		t = "OBJECTIVE: RATIONS — the cold room, past the galley door"
	elif _objective_state == "none":
		t = "OBJECTIVE: none — free sorties only, for now"
	if t != _objective_cached:
		_objective_cached = t
		hud.set_objective(t)


func _hud_pickup_message() -> void:
	if _cargo == "camera":
		hud.show_message("Video module secured.", 3.0)
		hud.set_objective("OBJECTIVE: video module — bring it home to the dock")
	elif _cargo == "rations":
		hud.show_message("Rations secured.", 3.0)
		hud.set_objective("OBJECTIVE: bring the rations home")
	_refresh_objective_text()


# --------------------------------------------------------------------------
# Hosts
# --------------------------------------------------------------------------

func _spawn_hosts() -> void:
	# The junction patroller. Every leg is routed through open space: leg C's
	# mouth, both junction mouths into the east annex, the ring corners, and
	# the cafeteria's south/west arches. Straight-line seek (no navmesh) is
	# safe only if the route is legal, so the annex legs hug the corridors.
	var patrol_points := [
		Vector3(-2.4, 0.0, -10.0),   # A  leg A
		Vector3(-2.4, 0.0, -15.0),   # G  bend, on the leg-A mouth line
		Vector3(0.2, 0.0, -15.2),    # B  bend, toward leg C
		Vector3(0.6, 0.0, -21.0),    # C  leg C
		Vector3(0.0, 0.0, -24.8),    # M2 junction approach
		Vector3(0.0, 0.0, -26.6),    # M1 junction mouth
		Vector3(-3.6, 0.0, -29.0),   # junction west sweep
		Vector3(3.2, 0.0, -30.0),    # junction east, toward the annex
		Vector3(5.4, 0.0, -29.6),    # spur mouth / west ring corner
		Vector3(8.2, 0.0, -29.0),    # south of the wreck
		Vector3(12.0, 0.0, -29.7),   # north ring
		Vector3(18.6, 0.0, -29.7),   # north ring east
		Vector3(20.1, 0.0, -29.7),   # NE corner
		Vector3(20.1, 0.0, -26.5),   # east ring
		Vector3(20.1, 0.0, -22.0),   # east ring, cafeteria east arch
		Vector3(20.1, 0.0, -18.5),   # east ring
		Vector3(20.1, 0.0, -16.8),   # SE corner
		Vector3(17.0, 0.0, -16.8),   # south ring east
		Vector3(12.0, 0.0, -16.8),   # south ring
		Vector3(12.0, 0.0, -18.2),   # cafeteria south arch
		Vector3(10.5, 0.0, -19.2),   # cafeteria south-west lane
		Vector3(7.0, 0.0, -22.0),    # cafeteria west arch
		Vector3(5.4, 0.0, -22.0),    # west ring
		Vector3(5.4, 0.0, -26.0),    # west ring north
		Vector3(2.8, 0.0, -26.2),    # junction, second mouth
		Vector3(0.0, 0.0, -26.6),    # M1 mouth again (the way back)
		Vector3(0.0, 0.0, -24.8),    # M2 leg C again
		Vector3(0.2, 0.0, -15.2),    # B  bend again
		Vector3(-2.4, 0.0, -15.0),   # G  leg-A mouth again
	]
	_host(Vector3(0.6, 0.2, -21.0), patrol_points)
	hosts[0]._wp = 3   # start at C, mid-loop: early launches aren't a coin toss
	# One ordinary host only. The galley is empty now: two patrolling silhouettes
	# made the opening rooms a traffic jam rather than a threat. The ship's
	# other bodies (the stalker, the Collector) live deeper in.


func _host(pos: Vector3, waypoints: Array) -> void:
	var host := CharacterBody3D.new()
	host.set_script(HOST)
	add_child(host)
	host.global_position = pos
	host.waypoints = waypoints
	host.reset()
	host.drone_caught.connect(_on_drone_caught.bind(host))
	NoiseBus.emitted.connect(host._on_noise)
	hosts.append(host)


## The Collector is not in the `hosts` list: it never kills and never joins a
## chase. It lives in the ship from the start, walking its remains route and
## feeding the Processor. It is also the only body that picks a chassis up
## without destroying it: the link and camera stay live through the whole ride.
func _spawn_collector() -> void:
	if collector != null and is_instance_valid(collector):
		return
	collector = CharacterBody3D.new()
	collector.set_script(COLLECTOR)
	add_child(collector)
	# Its home is still the old ossuary; only the deposit target moved to the
	# Processor pile, so the loop threads the new hall every pass.
	var route: Array = COLLECTOR_ROUTE.duplicate()
	var door_point: Vector3 = ship.COLLECTOR_DEPOSIT + Vector3(0, 0, -4.0)
	route[0] = ship.COLLECTOR_DEPOSIT
	route[1] = door_point
	route[route.size() - 1] = door_point
	var home: Vector3 = route[0]
	collector.global_position = Vector3(home.x, 0.2, home.z)
	collector.waypoints = route
	collector.remains = ship.remains
	collector.deposit_pos = ship.PROCESSOR_PILE
	collector.deposit_node = ship.processor_pile
	collector.bot_drop_pos = ship.PROCESSOR_DROP
	collector.bots = drones          # shared fleet reference: pickups see spawns
	collector.door_host = ship
	collector.bot_picked_up.connect(_on_bot_picked_up)
	collector.bot_delivered.connect(_on_bot_delivered)
	collector.reset()


## The Processor is a fixture, not a patrol: pinned in the feed chamber from
## the first act, waiting for the Collector's deliveries. It only ever moves
## its hands and jaw, and it only notices a chassis that is moving.
func _spawn_processor() -> void:
	if processor != null and is_instance_valid(processor):
		return
	processor = CharacterBody3D.new()
	processor.set_script(PROCESSOR)
	add_child(processor)
	processor.global_position = Vector3(ship.PROCESSOR_POS.x, 0.0,
			ship.PROCESSOR_POS.z)
	processor.rotation.y = PI * 0.5     # face west, toward the pile and hall
	processor.pile = ship.processor_pile
	processor.drone = null
	processor.reset()
	processor.drone_caught.connect(_on_drone_caught.bind(processor))


func _on_bot_picked_up(bot) -> void:
	if bot != drone or hud == null:
		return
	hud.show_message("LINK HELD — the Collector is carrying BOT %d."
			% (bot.bot_index + 1), 3.0)


func _on_bot_delivered(bot) -> void:
	if bot != drone or hud == null:
		return
	hud.show_message("BOT %d set down at the Processor. Drive." % (bot.bot_index + 1),
			3.0)


## The primary bad guy. It spawns in the far north ring when the drone enters
## the junction, then patrols / hears / chases on its own. It persists across
## sorties once spawned, so later runs share the ship with it.
func _spawn_m4_stalker() -> void:
	if _m4_host != null and is_instance_valid(_m4_host):
		return
	var stalker = CharacterBody3D.new()
	stalker.set_script(STALKER)
	add_child(stalker)
	var spawn_pt: Vector3 = STALKER_PATROL[0]
	stalker.global_position = Vector3(spawn_pt.x, 0.2, spawn_pt.z)
	stalker.waypoints = STALKER_PATROL.duplicate()
	stalker.hide_spots = ship.hide_spots
	stalker.ambush_spots = ship.ambush_spots
	stalker.chokes = ship.chokes
	stalker.reset()
	stalker.drone = drone
	stalker.drone_caught.connect(_on_drone_caught.bind(stalker))
	stalker.lunge_started.connect(_on_stalker_lunge)
	NoiseBus.emitted.connect(stalker._on_noise)
	hosts.append(stalker)
	_m4_host = stalker
	scanner.add_mass(stalker, 2.2)
	# A cold emergency lamp wakes in the junction. It gives the body and its
	# long shadow something to be seen against when it arrives.
	_m4_light = OmniLight3D.new()
	_m4_light.light_color = Color(0.78, 0.84, 1.0)
	_m4_light.light_energy = 1.0
	_m4_light.omni_range = 9.5
	_m4_light.omni_attenuation = 1.0
	_m4_light.shadow_enabled = true
	_m4_light.position = Vector3(0.0, 2.8, -29.0)
	ship.add_child(_m4_light)
	Sfx.play("thud", stalker.global_position, -6.0)


func _on_stalker_lunge() -> void:
	# The player looked back. Sell it: stinger, a hard static lock and a red
	# flash while the body covers the last few metres.
	_static_lock = 0.9
	_static_boost = 0.6
	hud.jumpscare()
	Sfx.play("screech", Sfx.CENTER, 2.0)


func _on_drone_caught(host) -> void:
	if _reeling or GameState.sortie != GameState.Sortie.PILOTING or drone == null:
		return
	_reeling = true
	var caught = drone
	var dpos: Vector3 = caught.global_position
	# Losing the chassis loses whatever module it carried. The still camera is
	# standard kit, but the salvaged video module is a one-off and stays out
	# there in the wreck until someone goes back for it.
	var camera_loss: bool = _camera_installed or _cargo == "camera"
	caught.set_controlled(false)
	Sfx.play("thud", dpos, 2.0)
	Sfx.play("static", Sfx.CENTER, -6.0)
	_static_lock = 2.2
	hud.show_message("BOT %d caught." % (caught.bot_index + 1), 3.0)
	if camera_loss:
		_camera_installed = false
		ship.spawn_wreck(dpos)
		_camera_site_pos = dpos
		_act_stage = 2 if _act_stage >= 1 else 0
		_pending_end_card = true
	if _cargo == "rations":
		_objective_state = "pending"
	if _cargo != "":
		_cargo = ""
	_refresh_objective_text()
	await get_tree().create_timer(1.6, false).timeout
	if not is_inside_tree():
		return

	# The fleet absorbs the loss: only an empty fleet ends the sortie. The dead
	# chassis is destroyed where it fell and the link hops to a survivor.
	drones.erase(caught)
	caught.queue_free()
	if drones.is_empty():
		drone = null
		_reeling = false
		_teardown_sortie(true)
		return
	_drone_index = clampi(_drone_index, 0, drones.size() - 1)
	drone = drones[_drone_index]
	_cargo = drone.cargo
	_reeling = false
	drone.live_view = _live_feed_active()
	drone.set_controlled(true)
	_bind_active()
	# The catcher must let go of the chassis it just killed, or it stays
	# latched on a body that no longer exists. Its link is now the survivor.
	if host != null and is_instance_valid(host) and host.has_method("release_catch"):
		host.release_catch()
	hud.set_piloting(true)
	_photo_show = 0.0
	hud.hide_photo()
	hud.show_message("BOT %d lost. Link → BOT %d."
			% [caught.bot_index + 1, drone.bot_index + 1], 3.0)
	if _pending_end_card:
		_show_module_loss_card()
	_refresh_objective_text()


# --------------------------------------------------------------------------
# Sortie state machine
# --------------------------------------------------------------------------

## Live video is the recovered module's perk. The master gate stays in the
## tree so the whole feed can be disabled in one place during tuning.
func _live_feed_active() -> bool:
	return VIDEO_FEED_ENABLED and _camera_installed


func _start_sortie() -> void:
	if not _started or _paused or _reeling:
		return
	if GameState.sortie == GameState.Sortie.PILOTING:
		return

	GameState.sortie = GameState.Sortie.PILOTING
	_reeling = false
	_dock_prompt = false
	_swap_cd = 0.0
	_deploy_cd = 0.0
	hud.set_prompt("")
	player.focus = null          # refresh the chair prompt from a clean slate

	Sfx.play("static", Sfx.CENTER, -8.0)
	_static_lock = 1.0

	# Resume the fleet you parked when you stood up. Each chassis keeps its own
	# world position, heading, charge and cargo; only a teardown frees them.
	if not drones.is_empty():
		_drone_index = clampi(_drone_index, 0, drones.size() - 1)
		drone = drones[_drone_index]
		_cargo = drone.cargo
		for d in drones:
			d.live_view = _live_feed_active()
		drone.set_controlled(true)
		_bind_active()
		hud.set_piloting(true)
		_photo_show = 0.0
		hud.hide_photo()
		if _live_feed_active():
			hud.show_message("Live feed resumed.", 2.4)
		else:
			hud.show_message("Link resumed. Radar + still camera.", 2.4)
		return

	# Fresh flight: one chassis on the hatch cradle. More are deployed one at
	# a time with B and left in the field; there is never a second body at
	# launch, so the cradle always reads as the player's own machine.
	_spawn_drone(0)
	_drone_index = 0
	drone = drones[0]
	drone.set_controlled(true)
	_cargo = drone.cargo
	_bind_active()
	hud.set_piloting(true)
	_photo_cd = 0.0
	_photo_show = 0.0
	hud.hide_photo()
	if _live_feed_active():
		hud.show_message("Live feed online. B deploys another bot, Q swaps.", 3.2)
	else:
		hud.show_message("Radar + still camera. B deploys another bot, Q swaps.", 3.2)


## Build one chassis on the first clear cradle at the dock. Bots deploy one at
## a time; later ones sit deeper in the ship corridor (negative z), never on
## the bay side of the sealed north wall. The bay is the player's safe room.
func _spawn_drone(slot: int) -> void:
	var d := CharacterBody3D.new()
	d.set_script(DRONE)
	add_child(d)
	d.global_position = _free_cradle_pos()
	d.dock_pos = ship.dock_pos
	d.anchor_pos = ship.dock_pos
	d.cargo = ""
	d.live_view = _live_feed_active()
	d.configure_bot(slot)
	d.feed_message.connect(hud.show_message)
	d.battery_dead.connect(_on_drone_battery_dead.bind(d))
	drones.append(d)


## First cradle in the corridor that no live chassis is already sitting on.
## All candidates are ship-side (negative z from the dock).
func _free_cradle_pos() -> Vector3:
	for n in 24:
		var p: Vector3 = ship.dock_pos + Vector3(0.0, 0.0, -DRONE_CRADLE_GAP * n)
		var clear := true
		for d in drones:
			if d != null and is_instance_valid(d) \
					and d.global_position.distance_to(p) < 1.1:
				clear = false
				break
		if clear:
			return p
	return ship.dock_pos + Vector3(0.0, 0.0, -DRONE_CRADLE_GAP * 24.0)


## Smallest unused bot number, so a replacement reuses the slot a lost chassis
## left behind ("BOT 2 back on the cradle") rather than climbing forever.
func _free_bot_slot() -> int:
	var used := {}
	for d in drones:
		if d != null and is_instance_valid(d):
			used[d.bot_index] = true
	for i in DRONE_FLEET:
		if not used.has(i):
			return i
	return DRONE_FLEET


## B while piloting: drop one new chassis on the dock cradle and put the link
## in it. The bot you were flying parks where it stood. One press, one bot.
func _deploy_drone() -> void:
	if GameState.sortie != GameState.Sortie.PILOTING or _paused or _reeling:
		return
	if _deploy_cd > 0.0 or drones.size() >= DRONE_FLEET:
		return
	var slot := _free_bot_slot()
	if slot >= DRONE_FLEET:
		return
	if drone != null and is_instance_valid(drone):
		drone.cargo = _cargo
		drone.velocity = Vector3.ZERO
		drone.set_controlled(false)
	_spawn_drone(slot)
	_drone_index = drones.size() - 1
	drone = drones[_drone_index]
	_cargo = drone.cargo
	drone.live_view = _live_feed_active()
	drone.set_controlled(true)
	_bind_active()
	hud.set_piloting(true)
	_photo_show = 0.0
	hud.hide_photo()
	_deploy_cd = 0.4
	Sfx.play("tick", Sfx.CENTER, -8.0)
	hud.show_message("BOT %d deployed at the dock." % (drone.bot_index + 1), 2.2)
	_refresh_objective_text()


## Rebind the shared senses and HUD to the active chassis. Nothing moves: the
## fleet's whole point is that the link is the only thing that transfers.
func _bind_active() -> void:
	if drone == null:
		return
	drone.live_view = _live_feed_active()
	for h in hosts:
		h.drone = drone
	# The Processor is in the hosts group but not in main.hosts: it has no
	# patrol or noise model, so it is bound explicitly.
	if processor != null and is_instance_valid(processor):
		processor.drone = drone
	scanner.drone = drone
	scanner.anchor_pos = ship.dock_pos
	hud.set_live_feed(_live_feed_active())
	hud.set_feed_enabled(true)
	hud.set_feed_source(_feed_vp)
	_refresh_chair_prompt()


func _fleet_line() -> String:
	if drones.is_empty():
		return ""
	var line := ""
	for i in drones.size():
		if i > 0:
			line += "    |    "
		var tag := "BOT %d" % (drones[i].bot_index + 1)
		if i == _drone_index:
			tag = "» " + tag
		var note := ""
		if drones[i].cargo == "rations":
			note = " [RAT]"
		elif drones[i].cargo == "camera":
			note = " [CAM]"
		line += "%s %3.0f%%%s" % [tag, drones[i].battery, note]
	if drones.size() < DRONE_FLEET:
		line += "    [B] DEPLOY"
	if drones.size() > 1:
		line += "    [Q] SWAP"
	return line


func _cycle_drone() -> void:
	if drones.size() < 2:
		return
	_switch_drone((_drone_index + 1) % drones.size())


## Move the link to another chassis. The old bot goes silent where it stands;
## the new one wakes with its own charge and cargo. Hosts track only the active
## bot, so a parked chassis is genuinely out of the conversation.
func _switch_drone(index: int) -> void:
	if GameState.sortie != GameState.Sortie.PILOTING or _reeling or _paused:
		return
	if drones.size() < 2 or _swap_cd > 0.0:
		return
	index = clampi(index, 0, drones.size() - 1)
	if index == _drone_index:
		return
	var old = drone
	if old != null and is_instance_valid(old):
		old.cargo = _cargo
		old.velocity = Vector3.ZERO
		old.set_controlled(false)
	_drone_index = index
	drone = drones[index]
	_cargo = drone.cargo
	drone.live_view = _live_feed_active()
	drone.set_controlled(true)
	for h in hosts:
		h.drone = drone
	if processor != null and is_instance_valid(processor):
		processor.drone = drone
	scanner.drone = drone
	scanner.anchor_pos = ship.dock_pos
	hud.set_live_feed(_live_feed_active())
	hud.set_feed_source(_feed_vp)
	hud.hide_photo()
	_photo_show = 0.0
	_swap_cd = 0.2
	_static_lock = maxf(_static_lock, 0.25)
	Sfx.play("tick", Sfx.CENTER, -8.0)
	hud.show_message("Link transferred to BOT %d." % (drone.bot_index + 1), 1.6)
	_refresh_objective_text()


## E while piloting: stand up. The drone is NOT torn down — it keeps its
## position, heading, charge and cargo. Hosts lose the scent (drone = null);
## the scanner goes dark until you sit back down. Press E at the chair again
## to resume exactly where you left it.
func _leave_chair() -> void:
	if GameState.sortie != GameState.Sortie.PILOTING or drone == null or _reeling:
		return
	drone.cargo = _cargo
	drone.velocity = Vector3.ZERO
	drone.set_controlled(false)
	scanner.drone = null
	for h in hosts:
		h.drone = null
	if processor != null and is_instance_valid(processor):
		processor.drone = null

	GameState.sortie = GameState.Sortie.IDLE
	player.cam.make_current()
	player.focus = null          # force a fresh focus ray + prompt next frame
	hud.set_live_feed(false)
	hud.set_piloting(false)
	hud.set_feed_enabled(true)
	hud.set_prompt("")
	hud.hide_photo()
	_photo_show = 0.0
	_dock_prompt = false
	_refresh_chair_prompt()
	Sfx.play("tick", Sfx.CENTER, -10.0)
	hud.show_message("Fleet parked. E at the chair resumes the link.", 2.8)


func _refresh_chair_prompt() -> void:
	if level == null or level.pilot_chair == null:
		return
	if drone != null and is_instance_valid(drone):
		level.pilot_chair.prompt = "Resume the drone"
	else:
		level.pilot_chair.prompt = "Sit - bring up the drone"


func _try_reel(force: bool) -> void:
	if drone == null or _reeling:
		return
	# Absorb the launch keypress and any echo tail: nothing reels during the
	# first ~0.5 s of GAME time (battery drain, identical arithmetic in
	# headless fast-loop or real play) unless forced.
	if not force and drone.battery >= 100.0 - DRONE.BATTERY_RATE * 0.5:
		return
	var near: bool = drone.global_position.distance_to(ship.dock_pos) < 6.0
	if not (force or near):
		hud.show_message("Bring the active bot to the hatch dock to reel.", 3.0)
		return
	_reeling = true
	drone.cargo = _cargo
	# The winch hauls the whole fleet home: every parked chassis comes back and
	# every cargo slot is delivered, not just the one you were flying.
	var has_rations := _fleet_has("rations")
	var has_camera := _fleet_has("camera")
	for d in drones:
		if d != null and is_instance_valid(d):
			d.set_controlled(false)
	Sfx.play("reel", Sfx.CENTER, -6.0)
	hud.show_message("Reeling fleet home.", 1.6)
	await get_tree().create_timer(1.1, false).timeout
	if not is_inside_tree():
		return
	if has_rations:
		GameState.kcal = minf(GameState.kcal + 30.0, 100.0)
		GameState.h2o = minf(GameState.h2o + 18.0, 100.0)
		_objective_state = "none"
		hud.show_message("Rations racked.", 2.0)
	if has_camera:
		_camera_held = true
		hud.show_message("Video module ready to install at the fabricator.", 3.0)
	_cargo = ""
	for d in drones:
		if d != null and is_instance_valid(d):
			d.cargo = ""
	_refresh_objective_text()
	_teardown_sortie(false)


func _at_fabricator() -> void:
	if _camera_held:
		_camera_held = false
		_camera_installed = true
		if _act_stage == 0:
			_act_stage = 1           # module aboard: the interception is armed
		elif _act_stage == 2:
			_act_stage = 3           # recovered and refitted: free sorties
		# The module is the live-feed decoder. Racked, it wakes up on the next
		# sortie; there is no feed while it is held in your hands.
		Sfx.play("thud", level.fabricator.global_position + Vector3(0, 0.4, 0), -4.0)
		hud.show_message("Video module racked. Live feed on the next sortie.", 3.0)
	else:
		hud.show_message("Nothing to install.", 2.0)
	_refresh_objective_text()


## The still-camera SubViewport, created at boot. Despite the historical
## "feed" name this is NOT live video: it renders exactly one frame per
## exposure (UPDATE_ONCE). Live video is the main-viewport handoff in
## `drone.live_view`, unlocked by the recovered module.
func _setup_feed() -> void:
	if _feed_vp == null:
		_feed_vp = SubViewport.new()
		_feed_vp.size = Vector2i(480, 270)
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_feed_cam = Camera3D.new()
		_feed_cam.fov = 62.0
		_feed_cam.near = 0.04
		_feed_vp.add_child(_feed_cam)
		add_child(_feed_vp)
	hud.set_feed_source(_feed_vp)
	hud.set_feed_enabled(true)


func _on_drone_battery_dead(d = null) -> void:
	if _reeling:
		return
	# Only the linked chassis drains, so a parked bot should never fire this.
	# If it somehow does, ignore it: the fleet keeps flying.
	if d != null and d != drone:
		return
	hud.show_message("Charge gone. Winching fleet home.", 2.6)
	_try_reel(true)


## One teardown: reel home (loss = false) or dragged away by force (true).
## The whole fleet is freed here; parking between sorties keeps it alive.
func _teardown_sortie(lost: bool) -> void:
	# The Collector may still be holding a chassis that is about to be freed;
	# let go before the fleet goes out from under it.
	if collector != null and is_instance_valid(collector):
		collector.release_carried()
	for d in drones:
		if d != null and is_instance_valid(d):
			d.set_controlled(false)
			d.queue_free()
	drones.clear()
	drone = null
	_drone_index = 0
	_cargo = ""
	scanner.drone = null
	_deploy_cd = 0.0
	for h in hosts:
		h.drone = null
	if processor != null and is_instance_valid(processor):
		processor.drone = null
	GameState.sortie = GameState.Sortie.IDLE
	player.cam.make_current()
	player.focus = null          # refocus the bay, refresh the chair prompt
	hud.set_live_feed(false)
	hud.set_piloting(false)
	hud.set_fleet_line("")
	hud.set_feed_enabled(true)   # still camera is standard kit, not the module
	hud.set_prompt("")
	Sfx.play("static", Sfx.CENTER, -10.0)
	_static_lock = 1.0
	_reeling = false
	_dock_prompt = false
	hud.hide_photo()
	_photo_show = 0.0
	_refresh_chair_prompt()
	if _pending_end_card:
		_show_module_loss_card()


## The crash card for losing the video module. Shown at teardown when the
## fleet is gone, or immediately when a surviving chassis carries the run on.
func _show_module_loss_card() -> void:
	_pending_end_card = false
	hud.show_end_card("THE MODULE IS GONE",
		"Video module lost. Drones are back to the still camera until you recover it.",
		"Click to resume. Recover the module to restore live feed.")


func _signal_bars(dist: float) -> int:
	# Scaled for the 36 m drum: the far pantry sits at ~31.5 m — one bar, heavy
	# snow, deliberate.
	if dist < 10.0:
		return 5
	if dist < 17.0:
		return 4
	if dist < 24.0:
		return 3
	if dist < 30.0:
		return 2
	if dist < 36.0:
		return 1
	return 0


# --------------------------------------------------------------------------
# Environment / ambience
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.008, 0.011)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.30)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.045)
	env.fog_density = 0.030
	env.fog_sky_affect = 0.0
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)


func _hull_knock() -> void:
	var body_pos: Vector3 = drone.global_position if drone != null else player.global_position
	var ang := randf() * TAU
	var dist := randf_range(7.0, 15.0)
	var pos := body_pos + Vector3(
		sin(ang) * dist, randf_range(-2.0, 1.2), cos(ang) * dist)
	Sfx.play("knock", pos, -5.0, randf_range(0.8, 1.1))
	NoiseBus.emit_noise(pos, 0.3)
	if randf() < 0.35:
		get_tree().create_timer(randf_range(0.4, 0.9), false).timeout.connect(
			_knock_echo.bind(pos))


func _knock_echo(pos: Vector3) -> void:
	if not _paused:
		Sfx.play("knock", pos, -11.0, randf_range(0.85, 1.0))


func _refresh_meters() -> void:
	pass  # display refresh is throttled in _process; bus kept for later wiring
