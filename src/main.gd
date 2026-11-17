extends Node3D
## UMBILICAL orchestration: Deck A (ship + bay) and Deck B (Cold Hold).
##
## The opening ship is deliberately threat-free. The only monsters are the
## four aggressive bodies that wake in the Cold Hold the first time the active
## drone crosses the umbilical. There is no authored loss: losing a chassis
## (or the video module) is something the player earns by being seen, not a
## scripted interception. The wreck/module-recovery systems remain live for
## any loss that actually happens.
##
## M5: hull-borne sound routing (see sfx.gd), motor load pitch, feed jitter,
## and the hand-copy map — compartments only ink in once a drone has actually
## been there; Deck B gets its own inset sheet.
##
## M6b: the drone fleet. Chassis deploy one at a time at the dock and stay
## where they are left; `drone` is the linked one and `drones` holds the rest.
## Only the linked bot drains and steers; B deploys, Q / 1-2 move the link; a
## lost chassis is struck from the fleet and the link hops to a survivor.
##
## M7: the Cold Hold. Beyond the junction's north airlock, an eight-metre
## umbilical opens into a pitch-black 50 x 25 m hold. A relay inside keeps
## every hold point inside the 36 m tether. The first entry wakes four hunters,
## feeds the Collector to the Processor (one-shot), and arms the crawler
## set piece in the side hall.

const FAB_BAY_SCENE := preload("res://scenes/level/rooms/fab_bay.tscn")
const SHIP_SCENE := preload("res://scenes/level/ship.tscn")
const DRONE := preload("res://src/drone/drone.gd")
const DRONE_SCENE := preload("res://scenes/actors/drone.tscn")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const SCANNER := preload("res://src/ui/scanner.gd")
const HUD := preload("res://src/ui/hud.gd")
const MAP_VIEW := preload("res://src/ui/map_view.gd")
const HOST_SCENE := preload("res://scenes/actors/host.tscn")
const STALKER_SCENE := preload("res://scenes/actors/stalker.tscn")
const COLLECTOR_SCENE := preload("res://scenes/actors/collector.tscn")
const PROCESSOR_SCENE := preload("res://scenes/actors/processor.tscn")
const CRAWLER_SCENE := preload("res://scenes/actors/crawler.tscn")

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
## PSX world: every 3D node lives under PSXLook's SubViewport. HUD, map and
## still-photo viewport stay outside it so text and overlays stay sharp.
var psx_screen: PSXScreen
var world: Node3D
var _psx_open := false
var _psx_owned_pause := false
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
var _objective_state := "pending"   # flashlight errand (HUD bookkeeping)
var _cargo := ""                    # "", "flashlight", "camera"
var _camera_held := false
var _camera_installed := false
var _flashlight_held := false
var _flashlight_installed := false

# Act structure: 0 module not yet found / 1 module aboard / 2 module recovery
# (only if a real loss happens) / 3 free sorties after recovery.
var _act_stage := 0
var _camera_site_pos := Vector3.ZERO
var _pending_end_card := false

# --- Deck B / Cold Hold ----------------------------------------------------
var _zone2_entered := false       # active drone has crossed at least once
var _zone2_spawned := false       # four hunters exist (persist for the session)
var _zone2_dark := false          # current darkness target
var _zone2_beat_shown := false
var _collector_sacrifice_started := false
var _collector_sacrificed := false
var crawler = null
var _crawler_done := false
## Deck C: the engine-room Stalker. Spawned once at boot; it is the threat in
## the room beyond the crawler hall and persists for the session.
var stalker = null
var _stalker_spawned := false
var _env: Environment = null
var _ambient_base := 0.35
var _fog_base := 0.03
## A hunter must be on top of the crawler's spawn mark to defer it. Being
## anywhere in the open hold (or just inside the hall mouth) must not.
const HOST_CRAWLER_DEFER := 8.0

# --- Debug vision (F4) -----------------------------------------------------
# A developer-facing toggle: any chassis gets a clean full-colour live feed,
# the world is lit for low-light reading, and hostile bodies ignore the fleet.
var debug_vision := false
var _ambient_color_base := Color(0.18, 0.22, 0.3, 1.0)
var _tonemap_base := 1.0
const DEBUG_AMBIENT_ENERGY := 1.35
const DEBUG_AMBIENT_COLOR := Color(0.92, 0.95, 1.0, 1.0)
const DEBUG_FOG := 0.0
const DEBUG_EXPOSURE := 1.55
const DEBUG_LAMP_RANGE := 22.0

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

# Four authored Cold Hold patrol loops. Each stays clear of the crawler side
# hall (x > 19.2) and routes around the sparse cover. Straight-line seek is
# only safe when every leg is legal, so these are deliberately rectangular.
const ZONE2_ROUTES := [
	[Vector3(-24.0, 0.0, -61.0), Vector3(-24.0, 0.0, -49.0),
		Vector3(-14.0, 0.0, -49.0), Vector3(-14.0, 0.0, -61.0)],
	[Vector3(17.0, 0.0, -62.0), Vector3(12.0, 0.0, -62.0),
		Vector3(12.0, 0.0, -50.0), Vector3(17.0, 0.0, -50.0)],
	[Vector3(-25.0, 0.0, -45.0), Vector3(-13.0, 0.0, -45.0),
		Vector3(-13.0, 0.0, -52.0), Vector3(-25.0, 0.0, -52.0)],
	[Vector3(6.0, 0.0, -64.0), Vector3(-4.0, 0.0, -64.0),
		Vector3(-4.0, 0.0, -57.0), Vector3(6.0, 0.0, -57.0)],
]

# The engine room's Stalker owns the machinery floor: a wide rectangle around
# the core, clear of the low cover and the entry throat.
const ENGINE_ROUTE := [
	Vector3(15.0, 0.0, -72.0), Vector3(29.0, 0.0, -72.0),
	Vector3(29.0, 0.0, -83.0), Vector3(15.0, 0.0, -83.0),
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

# The kill close-up. When a live-feed chassis is caught, the tube cuts to a
# tight, randomly framed patch of the catcher's face for a few frames before
# the signal dies. The camera is staged in world space from the head bone; it
# never follows the drone camera, so losing the module cannot cancel the beat.
const CATCH_FACE_HOLD := 0.20       # ~12 rendered frames at 60 fps; still a brief beat
const CATCH_FACE_MIN_FRAMES := 2
const CATCH_FACE_FOV := 58.0
const CATCH_FACE_CLEARANCE := 0.10  # metres outside the head surface
var _catch_cam_active := false
var _catch_cam_xform := Transform3D.IDENTITY
var _catch_cam_fov := CATCH_FACE_FOV
var _catch_hold := 0.0
var _catch_frames := 0
## After the face hold the viewport is frozen on the last frame, then snow
## takes over. This keeps `_sync_feed_view` from resuming the drone camera if
## a live source (debug vision) survives the catch.
var _catch_frozen := false
## Last staged geometry, kept readable for probes and tuning.
var last_catch_face: Dictionary = {}
var _catch_rng := RandomNumberGenerator.new()

## The live tube is near-sighted: its lens loses focus a few metres out, so a
## still exposure is the only way to read the far end of a room. The still
## camera switches this off before it renders.
var _feed_attrs: CameraAttributesPractical = null
var _video_optics_on := false
const LIVE_DOF_FAR := 6.5      # metres before the video lens starts to soften
const LIVE_DOF_TRANSITION := 7.5
const LIVE_DOF_AMOUNT := 0.10
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
	_bind_psx()
	level = FAB_BAY_SCENE.instantiate()
	_add_world(level)
	# The table's paper quad carries the live map ViewportTexture. It must not
	# be converted to a PSX material or the texture would stop sampling.
	level.map_surface.set_meta("psx_exclude", true)
	level.pilot_chair.on_interact = Callable(self, "_start_sortie")
	level.fabricator.on_interact = Callable(self, "_at_fabricator")

	ship = SHIP_SCENE.instantiate()
	_add_world(ship)
	_camera_site_pos = ship.CAMERA_POS

	_setup_table_map()

	# Deck B darkness is driven per-frame by PSXLook, which owns the runtime
	# duplicate of the authored Environment.
	_env = PSXLook.environment
	if _env != null:
		_ambient_base = _env.ambient_light_energy
		_fog_base = _env.fog_density
		_ambient_color_base = _env.ambient_light_color
		_tonemap_base = _env.tonemap_exposure

	# Zone 1 is threat-free by design. Hosts only wake in the Cold Hold.
	_spawn_collector()
	_spawn_processor()

	hud = CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)
	hud.start_clicked.connect(_on_start_clicked)
	hud.resume_clicked.connect(_on_resume_clicked)
	hud.psx_open_requested.connect(_on_psx_open_requested)
	hud.psx_closed.connect(_on_psx_closed)

	# The still camera exists from the first launch; there is no install gate.
	_setup_feed()
	_catch_rng.randomize()

	player = PLAYER_SCENE.instantiate()
	_add_world(player)
	player.position = level.player_start
	player.rotation.y = PI * 0.5
	player.focus_changed.connect(hud.set_prompt)
	player.interact_pressed.connect(_on_interact_pressed)
	player.leave_requested.connect(_leave_chair)
	if collector != null and is_instance_valid(collector):
		collector.player_body = player

	scanner = SCANNER.new()
	scanner.drone = null
	scanner.anchor_pos = ship.dock_pos
	scanner.echo_recorded.connect(_on_wall_charted)
	hud.add_scanner(scanner)

	# Deck C's tenant. It patrols the engine room from the start; the player
	# cannot reach it until the crawler hall opens.
	_spawn_engine_stalker()

	_refresh_objective_text()
	_refresh_chair_prompt()
	hud.set_meters(GameState.o2, GameState.h2o, GameState.kcal, GameState.clock_hours)
	GameState.meters_changed.connect(_refresh_meters)

	# Now that the bay, ship and first inhabitants exist, convert and, if the
	# saved settings ask for it, densify them.
	PSXLook.refresh()


## Wire the authored scene hierarchy to PSXLook. The SubViewport owns its own
## World3D, so every gameplay Node3D must be added through _add_world().
func _bind_psx() -> void:
	psx_screen = get_node("WorldLayer/PSXScreen") as PSXScreen
	world = psx_screen.viewport.get_node("World") as Node3D
	var world_env := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	PSXLook.bind(self, psx_screen, world, world_env)


func _add_world(node: Node) -> void:
	world.add_child(node)


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
		var zone: String = _zone_at(dpos)
		var in_zone2 := zone == "zone2" or zone == "crawler"
		# The tether follows the active chassis across each threshold. The
		# active drone's own `anchor_pos` is what the physics clamp reads.
		_apply_anchor(drone, zone)
		var anchor: Vector3 = _anchor_for_zone(zone, dpos)
		var dist: float = dpos.distance_to(anchor)
		var bars := _signal_bars(dist)
		# Distance from the winch is a readout, not a fault: the live tube stays
		# clean out to the relay. Static is only the authored story beats below.
		hud.set_drone_status(dist, drone.MAX_TETHER, bars, drone.battery)
		hud.set_fleet_line(_fleet_line())

		# Live-tube stress: the picture tears and ghosts with the chassis.
		if stalker != null and is_instance_valid(stalker):
			stalker.feed_active = _live_feed_active()
		if _live_feed_active() and not debug_vision:
			var planar := Vector2(drone.velocity.x, drone.velocity.z).length()
			var speed_n := clampf(planar / DRONE.HURRY_SPEED, 0.0, 1.0)
			var steer := Input.get_axis("move_left", "move_right")
			# Half the old tear/ghost/dread amplitude: the feed still reads as
			# a worn tube, but it no longer swamps the picture.
			hud.set_live_stress(maxf(speed_n, absf(steer) * 0.35) * 0.5, -steer * 0.5)
			# The nearest Cold Hold body poisons the feed as it closes. This
			# is a readability cue, not a hidden tracker: it uses the same
			# distance the player can see on radar.
			var dread := 0.0
			var near_host = _nearest_host(dpos)
			if near_host != null:
				var md: float = dpos.distance_to(near_host.global_position)
				dread = pow(clampf(1.0 - md / 9.0, 0.0, 1.0), 1.4)
			hud.set_live_dread(dread * 0.5)
		elif debug_vision:
			# Clean debug picture: no tube stress, ghosting or proximity poison.
			hud.set_live_stress(0.0, 0.0)
			hud.set_live_dread(0.0)

		# Reel prompt appears only when the winch can actually take it.
		var near_dock := dpos.distance_to(ship.dock_pos) < 6.0
		if near_dock != _dock_prompt:
			_dock_prompt = near_dock
			hud.set_prompt("[R] REEL" if near_dock else "")

		# The map inks itself with travel: only places the drone has been.
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
			elif _flashlight_waiting() \
					and dpos.distance_to(ship.FLASHLIGHT_POS) < 1.7:
				_cargo = "flashlight"
				drone.cargo = _cargo
				if ship.flashlight_pickup != null:
					ship.flashlight_pickup.visible = false
				_hud_pickup_message()

		# The galley door: grind it open when close. Loud and witnessed. Once
		# open it stays open; the room is a shortcut to the cold store now.
		if not ship.galley_door_open and dpos.distance_to(ship.GALLEY_DOOR_POS) < 2.4:
			ship.open_galley_door()

		# The Deck B airlock lifts once and stays traversable. The approach
		# point comes from the editor-owned threshold anchor, not a literal.
		if not ship.zone2_door_open \
				and dpos.distance_to(ship.zone2_threshold) < 3.2:
			ship.open_zone2_door()

		# First active-drone entry into the Cold Hold arms the zone.
		if in_zone2:
			_on_active_enter_zone2()
			# The crawler is a one-shot, and defers while a hunter is close.
			if zone == "crawler":
				_try_start_crawler(dpos)
		if crawler != null and is_instance_valid(crawler) and not _crawler_done \
				and zone != "crawler":
			crawler.abandon()
		amt = 0.0 if debug_vision else minf(_static_boost + _static_lock, 1.0)
	_static_boost = maxf(_static_boost - delta * 0.9, 0.0)
	_static_lock = maxf(_static_lock - delta * 1.3, 0.0)
	hud.set_static_amount(amt)

	# Deck B is genuinely dark; Deck A keeps its authored ambient. The shift
	# is a slow fade so crossing the airlock reads as light dying behind you.
	var want_dark := GameState.sortie == GameState.Sortie.PILOTING and drone != null \
			and _zone_at(drone.global_position) in ["zone2", "crawler", "engine"]
	_set_zone2_dark(want_dark, delta)

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
	_sync_feed_view()
	_tick_catch_face(delta)

	if _map_open:
		hud.show_map(_map_data())


func _input(event: InputEvent) -> void:
	var f5key: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_F5 or event.keycode == KEY_F5)
	var psx_key: bool = (event.is_action_pressed("psx_menu") and not event.is_echo()) or f5key
	if _psx_open:
		if psx_key or event.is_action_pressed("pause") \
				or (event is InputEventKey and event.pressed and not event.echo \
					and event.physical_keycode == KEY_ESCAPE):
			_close_psx()
		return
	if psx_key:
		_open_psx()
		return
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
	# Raw L fallback for the flashlight: same stale-input-map defence.
	var lkey: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_L or event.keycode == KEY_L)
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
	# Raw F4 for the developer vision toggle, independent of the input map.
	var f4key: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_F4 or event.keycode == KEY_F4)
	if f4key and not _paused:
		_toggle_debug_vision()
		return
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
			and ((event.is_action_pressed("flashlight") and not event.is_echo()) or lkey):
		_toggle_flashlight()
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
	_feed_cam.fov = drone.cam.fov
	_feed_cam.global_transform = drone.cam.global_transform
	# A print is the good optic: clear focus out to the far end of the room,
	# unlike the near-sighted live tube. _sync_feed_view restores the video
	# lens once the print drops.
	_set_video_optics(false)
	# UPDATE_ONCE: exactly one render per photograph. If live video is running
	# the feed viewport freezes for the hold, then resumes in _sync_feed_view.
	_feed_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	hud.set_feed_source(_feed_vp)
	hud.show_photo()
	Sfx.play("shutter", Sfx.CENTER, -8.0)
	hud.set_shutter(0.0)


## L while piloting. The light is a real trade: it widens every hunter's sight
## and makes a parked chassis visible, but it is the only way to read the hold.
func _toggle_flashlight() -> void:
	if drone == null or not is_instance_valid(drone):
		return
	if not drone.flashlight_installed:
		return
	drone.toggle_flashlight()
	Sfx.play("tick", Sfx.CENTER, -8.0)


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


## F5 / the title and pause buttons. The panel is crisp UI outside the PSX
## screen. Opening it freezes play and releases the mouse.
func _open_psx() -> void:
	if _psx_open:
		return
	_psx_open = true
	if _started and not _paused:
		_toggle_pause()
		_psx_owned_pause = true
	hud.open_psx_panel()


func _close_psx() -> void:
	if not _psx_open:
		return
	_psx_open = false
	hud.close_psx_panel()
	if _psx_owned_pause and _paused:
		_toggle_pause()
	_psx_owned_pause = false


func _on_psx_open_requested() -> void:
	_open_psx()


func _on_psx_closed() -> void:
	# The panel's own Close button and F5/Escape share one exit path.
	if _psx_open:
		_close_psx()


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
		"flashlight_pending": _flashlight_waiting(),
		"flashlight_pos": ship.FLASHLIGHT_POS,
		"camera_installed": _camera_installed,
		"visited": _visited_zones,
		"charted": _charted_pts,
		"relay": ship.zone2_relay,
		"engine_relay": ship.engine_relay,
		"zone2_visited": _visited_zones.has("zone2") or _visited_zones.has("crawler"),
		"engine_visited": _visited_zones.has("engine"),
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
## the flashlight add-on.
func _fleet_has(kind: String) -> bool:
	if _cargo == kind:
		return true
	for d in drones:
		if d != drone and d.cargo == kind:
			return true
	return false


## The add-on is still on the cold-room shelf: not carried, not in the bay,
## not fitted. Keeps the world prop and the map marker in step with the run.
func _flashlight_waiting() -> bool:
	return _objective_state == "pending" and not _flashlight_held \
			and not _flashlight_installed and _cargo != "flashlight" \
			and not _fleet_has("flashlight")


## Render the hand-copy map onto the physical table paper (live radar ink).
## The bay is the one room that shows your knowledge without an overlay.
func _setup_table_map() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_table_map = MAP_VIEW.new()
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


## F3 diagnostics: total hostile roster, Deck B hunter count, nearest body.
func _host_debug() -> String:
	var total := hosts.size() + (1 if stalker != null and is_instance_valid(stalker) else 0)
	if total == 0:
		return "enemies 0  zone2 hosts 0"
	var ref: Vector3 = drone.global_position if drone != null else player.global_position
	var near = _nearest_host(ref)
	if near == null:
		return "enemies %d  zone2 hosts %d" % [total, hosts.size()]
	var names := ["PATROL", "CURIOUS", "HUNT", "STALK"]
	if near == stalker:
		names = ["PATROL", "INVESTIGATE", "SEARCH", "CHASE", "LURK", "LUNGE",
				"AMBUSH_SETUP", "AMBUSH"]
	var state_name: String = names[int(near.state)]
	return "enemies %d  zone2 hosts %d  nearest %s %.1fm  pos (%.1f, %.1f)  v %.2f" % [
		total, hosts.size(), state_name, ref.distance_to(near.global_position),
		near.global_position.x, near.global_position.z,
		Vector2(near.velocity.x, near.velocity.z).length(),
	]


func _zone_at(p: Vector3) -> String:
	# Deck C: the engine room and its new wings, north hall and upper gangway.
	if p.z < -66.2 and p.z > -96.4 and p.x > -2.2 and p.x < 46.4:
		return "engine"
	# Deck B: the enlarged hold (west rooms + north hall) and crawler hall.
	if p.z < -40.8:
		if p.x > 19.2 and p.z < -47.0 and p.z > -66.2:
			return "crawler"
		return "zone2"
	if p.z < -32.8 and p.z > -40.8 and absf(p.x) < 1.5:
		return "zone2"
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
	if _cargo == "flashlight":
		t = "CARRY: LIGHT -> DOCK"
	elif _cargo == "camera":
		t = "CARRY: VIDEO -> DOCK"
	elif _flashlight_held and _camera_held:
		t = "INSTALL: LIGHT + VIDEO"
	elif _flashlight_held:
		t = "INSTALL: LIGHT"
	elif _camera_held:
		t = "INSTALL: VIDEO"
	elif not _flashlight_installed and _objective_state == "pending":
		if _act_stage == 0 and not _camera_installed:
			t = "LIGHT: COLD ROOM\nVIDEO: EAST SPUR"
		else:
			t = "LIGHT: COLD ROOM"
	elif not _camera_installed:
		if _act_stage == 2:
			t = "RECOVER: VIDEO"
		elif _act_stage == 0:
			t = "VIDEO: EAST SPUR"
		else:
			t = "VIDEO: RETURN TO DOCK"
	elif _act_stage == 1:
		t = "VIDEO ABOARD"
	elif _objective_state == "pending":
		t = "LIGHT: COLD ROOM"
	elif _objective_state == "none":
		t = "NO TASK"
	if t != _objective_cached:
		_objective_cached = t
		hud.set_objective(t)
	if ship != null and ship.flashlight_pickup != null:
		ship.flashlight_pickup.visible = _flashlight_waiting()


func _hud_pickup_message() -> void:
	if _cargo == "camera":
		hud.show_message("VIDEO TAKEN", 3.0)
	elif _cargo == "flashlight":
		hud.show_message("LIGHT TAKEN", 3.0)
	_refresh_objective_text()


# --------------------------------------------------------------------------
# Hosts
# --------------------------------------------------------------------------

## The four Cold Hold hunters. Called once, on the first active-drone entry;
## they persist for the session. Spawn points are 20+ m from the threshold, so
## crossing the airlock never ends in an instant kill.
func _spawn_zone2_hosts(force := false) -> void:
	if _zone2_spawned and not force:
		return
	_zone2_spawned = true
	for i in mini(ship.zone2_spawns.size(), 4):
		var route: Array = ZONE2_ROUTES[i % ZONE2_ROUTES.size()].duplicate()
		var h = _host(ship.zone2_spawns[i], route, true)
		# Start on the leg nearest the authored spawn, not always index 0.
		h._wp = _nearest_route_point(h, route)
		h.drone = drone


func _nearest_route_point(h, route: Array) -> int:
	var best := 0
	var best_d := INF
	for i in route.size():
		var d: float = h.global_position.distance_to(route[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _host(pos: Vector3, waypoints: Array, aggressive := false):
	var host := HOST_SCENE.instantiate()
	if aggressive:
		host.configure_aggressive()
	host.ghosted = debug_vision
	_add_world(host)
	PSXLook.convert_subtree(host)
	host.global_position = pos
	host.waypoints = waypoints
	host.reset()
	host.drone_caught.connect(_on_drone_caught.bind(host))
	NoiseBus.emitted.connect(host._on_noise)
	hosts.append(host)
	return host


func _nearest_host(pos: Vector3):
	var best = null
	var best_d := INF
	var candidates: Array = hosts.duplicate()
	if stalker != null and is_instance_valid(stalker):
		candidates.append(stalker)
	for h in candidates:
		if h == null or not is_instance_valid(h):
			continue
		var d: float = pos.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	return best


## The side hallway is deliberately outside every hunter's route. A hunter
## that is merely patrolling the open hold near the hall mouth must NOT defer
## the set piece: that was the bug that kept the crawler from ever starting.
## Only a body actually in the hall, down by the crawl origin, competes.
func _try_start_crawler(dpos: Vector3) -> void:
	if _crawler_done or (crawler != null and is_instance_valid(crawler) and not crawler.done):
		return
	var watchers: Array = hosts.duplicate()
	if stalker != null and is_instance_valid(stalker):
		watchers.append(stalker)
	for h in watchers:
		if h == null or not is_instance_valid(h):
			continue
		var hp: Vector3 = h.global_position
		if _zone_at(hp) == "crawler" \
				and hp.distance_to(ship.crawler_grab) < HOST_CRAWLER_DEFER:
			return
	crawler = CRAWLER_SCENE.instantiate()
	_add_world(crawler)
	PSXLook.convert_subtree(crawler)
	crawler.drone = drone
	crawler.entrance = ship.crawler_setpiece
	crawler.grab_mark = ship.crawler_grab
	crawler.says.connect(_on_crawler_says)
	crawler.finished.connect(_on_crawler_finished)
	crawler.start(ship.crawler_grab, ship.crawler_setpiece)
	if _live_feed_active():
		# Let the player see it on the tube, but keep the picture legible.
		hud.set_live_dread(0.0)
	else:
		# Still-camera players get one honest exposure hit as it resolves out
		# of the dark: the lamp catches a shape for a single frame.
		hud.exposure_flash(0.30)
	hud.show_subtitle("SIDE HALL: MOVEMENT", 3.0)


func _on_crawler_says(text: String) -> void:
	hud.show_subtitle(text, 2.8)


func _on_crawler_finished() -> void:
	_crawler_done = true
	hud.show_subtitle("SIDE HALL: CLEAR", 3.0)
	Sfx.play("wet_snap", ship.crawler_setpiece, -2.0, 0.72)


## Deck C's tenant: one Stalker on the engine-room floor. It is a real enemy,
## so it can leave the room if it sees or hears the fleet; the room's low cover
## is the counterplay.
func _spawn_engine_stalker() -> void:
	if stalker != null and is_instance_valid(stalker):
		return
	_stalker_spawned = true
	stalker = STALKER_SCENE.instantiate()
	stalker.ghosted = debug_vision
	_add_world(stalker)
	PSXLook.convert_subtree(stalker)
	stalker.global_position = ship.engine_stalker_spawn
	stalker.waypoints = ENGINE_ROUTE.duplicate()
	stalker.hide_spots = ship.hide_spots
	stalker.ambush_spots = ship.ambush_spots
	stalker.chokes = ship.chokes
	# Lair tuning: it starts folded into a wall niche, hunts slowly for a
	# while, folds into a *different* corner, then hunts again.
	stalker.ambush_chance = 0.95
	stalker.ambush_roll = 2.5
	stalker.ambush_cooldown = 4.0
	stalker.ambush_wait = 12.0
	stalker.hunt_duration = 16.0
	stalker.patrol_speed = 0.55
	stalker.reset()
	stalker._enter_ambush()
	stalker.drone = null
	stalker.drone_caught.connect(_on_drone_caught.bind(stalker))
	stalker.lunge_started.connect(_on_stalker_lunge)
	NoiseBus.emitted.connect(stalker._on_noise)
	if scanner != null:
		scanner.add_mass(stalker, 2.2)


func _on_stalker_lunge() -> void:
	# The player looked back. Sell it: stinger, a hard static lock and a flash
	# while the body covers the last few metres.
	_static_lock = maxf(_static_lock, 1.0)
	_static_boost = maxf(_static_boost, 0.7)
	hud.jumpscare()
	Sfx.play("screech", Sfx.CENTER, 2.0)


func _set_zone2_dark(on: bool, delta: float) -> void:
	_zone2_dark = on
	PSXLook.set_zone_dark(on, delta)


## F4. Debug vision is deliberately blunt: clean colour drone video on any
## chassis (no module required), enough ambient light to read the dark hold,
## and hostile bodies ignore the fleet. Everything restores on the next press.
func _toggle_debug_vision() -> void:
	debug_vision = not debug_vision
	for h in hosts:
		if h != null and is_instance_valid(h):
			h.ghosted = debug_vision
	if processor != null and is_instance_valid(processor):
		processor.ghosted = debug_vision
	if collector != null and is_instance_valid(collector):
		collector.ghosted = debug_vision
	if stalker != null and is_instance_valid(stalker):
		stalker.ghosted = debug_vision
	# PSXLook suspends the whole look (screen, materials, fog, draw distance)
	# while debug vision is active, then restores the user's settings.
	PSXLook.set_debug_vision(debug_vision)

	var zone := "bay"
	if GameState.sortie == GameState.Sortie.PILOTING \
			and drone != null and is_instance_valid(drone):
		zone = _zone_at(drone.global_position)
	var dark := zone == "zone2" or zone == "crawler" or zone == "engine"
	_set_zone2_dark(dark, 1.0)

	hud.set_debug_view(debug_vision)
	if GameState.sortie == GameState.Sortie.PILOTING and drone != null \
			and is_instance_valid(drone):
		if debug_vision:
			drone.live_view = true
			drone.cam.make_current()
			hud.set_feed_source(_feed_vp)
			hud.set_feed_enabled(true)
			hud.set_live_feed(true)
		else:
			drone.live_view = _live_feed_active()
			if drone.live_view:
				drone.cam.make_current()
			else:
				player.cam.make_current()
				drone.live_view = false
			hud.set_live_feed(drone.live_view)
			hud.set_feed_enabled(true)
		_apply_anchor(drone, zone)
	if debug_vision:
		hud.show_message("DEBUG ON", 2.0)
	else:
		hud.show_message("DEBUG OFF", 2.0)


## The Collector is not in the `hosts` list: it never kills and never joins a
## chase. It lives in the ship from the start, walking its remains route and
## feeding the Processor. It is also the only body that picks a chassis up
## without destroying it: the link and camera stay live through the whole ride.
func _spawn_collector() -> void:
	if collector != null and is_instance_valid(collector):
		return
	collector = COLLECTOR_SCENE.instantiate()
	collector.ghosted = debug_vision
	_add_world(collector)
	PSXLook.convert_subtree(collector)
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
	collector.sacrifice_finished.connect(_on_collector_sacrificed)
	collector.reset()
	# Route point 0 is the nest itself. Start on the next point so the body is
	# already walking when the scene opens instead of resting on its spawn mark.
	if collector.waypoints.size() > 1:
		collector._wp = 1
		collector._rest = 0.0


## The Processor is a fixture, not a patrol: pinned in the feed chamber from
## the first act, waiting for the Collector's deliveries. It only ever moves
## its hands and jaw, and it only notices a chassis that is moving.
func _spawn_processor() -> void:
	if processor != null and is_instance_valid(processor):
		return
	processor = PROCESSOR_SCENE.instantiate()
	processor.ghosted = debug_vision
	_add_world(processor)
	PSXLook.convert_subtree(processor)
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
	hud.show_message("COLLECTOR: BOT %d" % (bot.bot_index + 1), 3.0)


func _on_bot_delivered(bot) -> void:
	if bot != drone or hud == null:
		return
	hud.show_message("BOT %d: PROCESSOR" % (bot.bot_index + 1), 3.0)


## The four hunters wake on first entry. The Collector gives itself to the
## Processor in the same beat: one visible/audible act, then Deck A is free of
## both the opening patrol and the wandering scavenger.
func _on_active_enter_zone2() -> void:
	if _zone2_entered:
		return
	_zone2_entered = true
	_spawn_zone2_hosts()
	if not _zone2_beat_shown:
		_zone2_beat_shown = true
		hud.show_zone_beat("DECK B", "")
		Sfx.play("zone_cue", Sfx.CENTER, -4.0)
		_static_lock = 0.5
	_start_collector_sacrifice()


func _start_collector_sacrifice() -> void:
	if _collector_sacrifice_started or _collector_sacrificed:
		return
	_collector_sacrifice_started = true
	if collector != null and is_instance_valid(collector):
		collector.begin_sacrifice(ship.collector_sacrifice)
		hud.show_subtitle("COLLECTOR: GONE", 3.0)


func _on_collector_sacrificed() -> void:
	if _collector_sacrificed:
		return
	_collector_sacrificed = true
	if processor != null and is_instance_valid(processor):
		processor.set_dormant(true)
	# The maw's last work is heard through the hull, long after the player can
	# see the chamber. The wing is inert from here on.
	Sfx.play("wet_snap", ship.collector_sacrifice, -4.0)
	Sfx.play("wet_crunch", ship.collector_sacrifice, -6.0, 0.82)
	hud.show_subtitle("PROCESSOR: DORMANT", 3.0)


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
	# One last look through the tube: stage the face beat before losing the
	# module, and only when a live feed is actually up. Still-only builds keep
	# the old immediate snow so no phantom face appears.
	var face_staged := false
	if _live_feed_active():
		face_staged = _stage_catch_face(host)
	if not face_staged:
		Sfx.play("static", Sfx.CENTER, -6.0)
		_static_lock = 2.2
	hud.show_message("BOT %d LOST" % (caught.bot_index + 1), 3.0)
	if camera_loss:
		_camera_installed = false
		ship.spawn_wreck(dpos)
		_camera_site_pos = dpos
		_act_stage = 2 if _act_stage >= 1 else 0
		_pending_end_card = true
	if _cargo == "flashlight":
		_objective_state = "pending"
		if ship.flashlight_pickup != null:
			ship.flashlight_pickup.visible = true
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
		_clear_catch_face()
		_teardown_sortie(true)
		return
	_drone_index = clampi(_drone_index, 0, drones.size() - 1)
	drone = drones[_drone_index]
	_cargo = drone.cargo
	_reeling = false
	drone.live_view = _live_feed_active()
	drone.set_controlled(true)
	_bind_active()
	_clear_catch_face()
	# The catcher must let go of the chassis it just killed, or it stays
	# latched on a body that no longer exists. Its link is now the survivor.
	if host != null and is_instance_valid(host) and host.has_method("release_catch"):
		host.release_catch()
	hud.set_piloting(true)
	_photo_show = 0.0
	hud.hide_photo()
	hud.show_message("LINK: BOT %d" % (drone.bot_index + 1), 3.0)
	if _pending_end_card:
		_show_module_loss_card()
	_refresh_objective_text()


# --------------------------------------------------------------------------
# Sortie state machine
# --------------------------------------------------------------------------

## Live video is the recovered module's perk. The master gate stays in the
## tree so the whole feed can be disabled in one place during tuning.
func _live_feed_active() -> bool:
	return debug_vision or (VIDEO_FEED_ENABLED and _camera_installed)


func _start_sortie() -> void:
	if not _started or _paused or _reeling:
		return
	if GameState.sortie == GameState.Sortie.PILOTING:
		return

	GameState.sortie = GameState.Sortie.PILOTING
	_reeling = false
	_clear_catch_face()
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
			d.set_flashlight(_flashlight_installed)
		drone.set_controlled(true)
		_bind_active()
		hud.set_piloting(true)
		_photo_show = 0.0
		hud.hide_photo()
		hud.show_message("LIVE" if _live_feed_active() else "STILL", 1.8)
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
	hud.show_message("LIVE" if _live_feed_active() else "STILL", 1.8)


## Build one chassis on the first clear cradle at the dock. Bots deploy one at
## a time; later ones sit deeper in the ship corridor (negative z), never on
## the bay side of the sealed north wall. The bay is the player's safe room.
func _spawn_drone(slot: int) -> void:
	var d := DRONE_SCENE.instantiate()
	_add_world(d)
	PSXLook.convert_subtree(d)
	d.global_position = _free_cradle_pos()
	d.dock_pos = ship.dock_pos
	d.anchor_pos = ship.dock_pos
	d.cargo = ""
	d.live_view = _live_feed_active()
	d.configure_bot(slot)
	d.set_flashlight(_flashlight_installed)
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
	hud.show_message("BOT %d DEPLOYED" % (drone.bot_index + 1), 1.8)
	_refresh_objective_text()


## Point every sensing body at the linked chassis (or at nothing).
func _bind_senses(target) -> void:
	for h in hosts:
		h.drone = target
	# The Processor is in the hosts group but not in main.hosts: it has no
	# patrol or noise model, so it is bound explicitly.
	if processor != null and is_instance_valid(processor):
		processor.drone = target
	if crawler != null and is_instance_valid(crawler) and not crawler.done:
		crawler.drone = target
	if stalker != null and is_instance_valid(stalker):
		stalker.drone = target
	scanner.drone = target
	if target != null:
		_apply_anchor(target, _zone_at(target.global_position))


## The anchor a zone is tethered to.
func _anchor_for_zone(zone: String, pos: Vector3 = Vector3.ZERO) -> Vector3:
	if zone == "engine":
		return _nearest_relay(pos, [ship.engine_relay, ship.engine_far_relay])
	if zone == "zone2" or zone == "crawler":
		return _nearest_relay(pos, [ship.zone2_relay, ship.zone2_west_relay,
				ship.zone2_north_relay])
	return ship.dock_pos


## Pick the relay closest to the chassis so an expanded room stays inside a
## 36 m drum without ever raising the tether length.
func _nearest_relay(pos: Vector3, relays: Array) -> Vector3:
	var best: Vector3 = relays[0]
	var best_d := INF
	for r in relays:
		var d: float = pos.distance_to(r)
		if d < best_d:
			best_d = d
			best = r
	return best


## Move a chassis' tether origin and the scanner's home marker together. Each
## relay keeps every point of its room inside the same 36 m drum; MAX_TETHER is
## never raised.
func _apply_anchor(target, zone: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dark := zone == "zone2" or zone == "crawler" or zone == "engine"
	if dark:
		target.anchor_pos = _anchor_for_zone(zone, target.global_position)
	else:
		target.anchor_pos = ship.dock_pos
	# The hold and engine room are black: before the flashlight add-on the omni
	# is only a close emergency glow, not a room-lighting cheat. After it is
	# racked, the narrow spot beam does the work and the omni stays near-field.
	if target.lamp != null:
		if debug_vision:
			target.lamp.omni_range = DEBUG_LAMP_RANGE
		elif target.flashlight_installed:
			target.lamp.omni_range = 2.2
		else:
			target.lamp.omni_range = 7.5 if dark else 3.4
	if target.flashlight != null:
		target.flashlight.spot_range = 24.0 if debug_vision else 18.0
		target.flashlight.light_energy = 4.2 if debug_vision else 3.2
	if scanner != null:
		scanner.anchor_pos = target.anchor_pos
		if zone == "engine":
			scanner.anchor_label = "ENGINE"
		elif dark:
			scanner.anchor_label = "RELAY"
		else:
			scanner.anchor_label = "DOCK"


## Rebind the shared senses and HUD to the active chassis. Nothing moves: the
## fleet's whole point is that the link is the only thing that transfers.
func _bind_active() -> void:
	if collector != null and is_instance_valid(collector):
		collector.player_target = drone
	if drone == null:
		return
	drone.live_view = _live_feed_active()
	_bind_senses(drone)
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
		if drones[i].cargo == "flashlight":
			note = " [FL]"
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
	_bind_senses(drone)
	hud.set_live_feed(_live_feed_active())
	hud.set_feed_source(_feed_vp)
	hud.hide_photo()
	_photo_show = 0.0
	_swap_cd = 0.2
	_static_lock = maxf(_static_lock, 0.25)
	Sfx.play("tick", Sfx.CENTER, -8.0)
	hud.show_message("LINK: BOT %d" % (drone.bot_index + 1), 1.4)
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
	_bind_senses(null)
	if crawler != null and is_instance_valid(crawler):
		crawler.abandon()

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
	_set_zone2_dark(false, 1.0)
	_refresh_chair_prompt()
	Sfx.play("tick", Sfx.CENTER, -10.0)
	hud.show_message("FLEET PARKED", 1.8)


func _refresh_chair_prompt() -> void:
	if level == null or level.pilot_chair == null:
		return
	if drone != null and is_instance_valid(drone):
		level.pilot_chair.prompt = "DRONE"
	else:
		level.pilot_chair.prompt = "SIT"


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
		hud.show_message("REEL: DOCK ONLY", 2.0)
		return
	_reeling = true
	drone.cargo = _cargo
	# The winch hauls the whole fleet home: every parked chassis comes back and
	# every cargo slot is delivered, not just the one you were flying.
	var has_flashlight := _fleet_has("flashlight")
	var has_camera := _fleet_has("camera")
	for d in drones:
		if d != null and is_instance_valid(d):
			d.set_controlled(false)
	Sfx.play("reel", Sfx.CENTER, -6.0)
	hud.show_message("REELING", 1.2)
	await get_tree().create_timer(1.1, false).timeout
	if not is_inside_tree():
		return
	if has_flashlight:
		_flashlight_held = true
		hud.show_message("LIGHT RECOVERED", 2.0)
	if has_camera:
		_camera_held = true
		hud.show_message("VIDEO RECOVERED", 2.0)
	_cargo = ""
	for d in drones:
		if d != null and is_instance_valid(d):
			d.cargo = ""
	_refresh_objective_text()
	_teardown_sortie(false)


func _at_fabricator() -> void:
	var notices: Array[String] = []
	if _flashlight_held:
		_flashlight_held = false
		_flashlight_installed = true
		_objective_state = "none"
		for d in drones:
			if d != null and is_instance_valid(d):
				d.set_flashlight(true)
		notices.append("LIGHT FITTED")
	if _camera_held:
		_camera_held = false
		_camera_installed = true
		if _act_stage == 0:
			_act_stage = 1           # module aboard: the interception is armed
		elif _act_stage == 2:
			_act_stage = 3           # recovered and refitted: free sorties
		# The module is the live-feed decoder. Racked, it wakes up on the next
		# sortie; there is no feed while it is held in your hands.
		notices.append("VIDEO FITTED")
	if notices.is_empty():
		hud.show_message("NO ITEM", 1.6)
	else:
		Sfx.play("thud", level.fabricator.global_position + Vector3(0, 0.4, 0), -4.0)
		hud.show_message("  |  ".join(notices), 2.4)
	_refresh_objective_text()


## The still-camera SubViewport, created at boot. Despite the historical
## "feed" name this is NOT live video: it renders exactly one frame per
## exposure (UPDATE_ONCE). Live video is the main-viewport handoff in
## `drone.live_view`, unlocked by the recovered module.
func _setup_feed() -> void:
	if _feed_vp == null:
		_feed_vp = SubViewport.new()
		_feed_vp.size = Vector2i(480, 270)
		# The still photo shares the PSX world (materials and lighting) but not
		# the PSX screen shader: the print keeps its own raw optical look.
		# The screen viewport owns its world, so use PSXLook.world_3d() (which
		# resolves find_world_3d()); its `world_3d` property is null.
		var feed_world := PSXLook.world_3d()
		assert(feed_world != null, "the still photo needs the PSX World3D")
		_feed_vp.world_3d = feed_world
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_feed_cam = Camera3D.new()
		_feed_cam.fov = 80.0
		_feed_cam.near = 0.04
		_feed_attrs = CameraAttributesPractical.new()
		_feed_attrs.dof_blur_far_enabled = false
		_feed_attrs.dof_blur_far_distance = LIVE_DOF_FAR
		_feed_attrs.dof_blur_far_transition = LIVE_DOF_TRANSITION
		_feed_attrs.dof_blur_amount = LIVE_DOF_AMOUNT
		_feed_cam.attributes = _feed_attrs
		_feed_vp.add_child(_feed_cam)
		add_child(_feed_vp)
	hud.set_feed_source(_feed_vp)
	hud.set_feed_enabled(true)


## The optics window is a viewport, not the whole screen. While live video is
## installed the viewport follows the active camera every frame; a held print
## leaves it frozen (UPDATE_ONCE) so the picture stays a photograph. Standing
## up stops the render entirely.
func _sync_feed_view() -> void:
	if _feed_vp == null or _feed_cam == null:
		return
	if _catch_cam_active:
		# The kill close-up overrides the normal live/still decision. It must
		# keep rendering even though the catch just took `_camera_installed`.
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_feed_cam.fov = _catch_cam_fov
		_feed_cam.global_transform = _catch_cam_xform
		_catch_frames += 1
		_set_video_optics(false)
		hud.set_feed_source(_feed_vp)
		return
	if _catch_frozen:
		# Leave the last face frame on the glass until the chassis is gone.
		_set_video_optics(false)
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var live := GameState.sortie == GameState.Sortie.PILOTING \
			and drone != null and is_instance_valid(drone) and _live_feed_active()
	if live and _photo_show <= 0.0:
		_feed_cam.fov = drone.cam.fov
		_feed_cam.global_transform = drone.cam.global_transform
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# The live feed is deliberately soft past a few metres. Debug vision
		# keeps the full clean picture so level work is not fought by the lens.
		_set_video_optics(not debug_vision)
	else:
		_set_video_optics(false)
		if GameState.sortie != GameState.Sortie.PILOTING:
			_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Resolve the authored catcher rig without owning its scene. Only the two
## zombies get a kill close-up: the Processor is a maw and the Collector cannot
## catch, so both must decline.
func _host_kind(host) -> String:
	if host == null or not is_instance_valid(host) or not (host is Node3D):
		return ""
	var scr := host.get_script() as Script
	if scr == null:
		return ""
	var path := scr.resource_path
	if path.ends_with("host/stalker.gd"):
		return "stalker"
	if path.ends_with("host/host.gd"):
		return "host"
	return ""


## Head centre, face axis and a conservative skull radius for a catcher.
func _resolve_catch_head(host) -> Dictionary:
	var kind := _host_kind(host)
	if kind == "host":
		var skeleton := host.get_node_or_null("Meshes/Model/Root/Skeleton3D") as Skeleton3D
		if skeleton == null:
			return {}
		var bone := skeleton.find_bone("Head")
		if bone < 0:
			return {}
		var head: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		var head_basis := head.basis.orthonormalized()
		return {
			"kind": kind,
			"centre": head.origin + head_basis.y * 0.09,
			"face": head_basis.z.normalized(),   # imported head bone faces +Z
			"radius": 0.17,
		}
	if kind == "stalker":
		var head_node := host.get_node_or_null("Rig/Hips/Torso/Head") as Node3D
		if head_node == null:
			return {}
		var stalker_basis := head_node.global_transform.basis.orthonormalized()
		return {
			"kind": kind,
			"centre": head_node.global_position,
			"face": -stalker_basis.z.normalized(),   # authored skull faces -Z
			"radius": 0.26,
		}
	return {}


## Pick one tight framing on the face hemisphere. Kept separate from the stage
## step so probes can sample many seeded picks without disturbing the feed.
func _pick_catch_face(host, rng: RandomNumberGenerator) -> Dictionary:
	var info := _resolve_catch_head(host)
	if info.is_empty():
		return {}
	var centre: Vector3 = info["centre"]
	var radius: float = info["radius"]
	var face: Vector3 = info["face"]
	# Stable orthonormal frame around the face axis, with a fallback for a
	# vertical head axis (looking straight up/down at the camera).
	var ref := Vector3.UP
	if absf(face.dot(ref)) > 0.95:
		ref = Vector3.RIGHT
	var right := ref.cross(face).normalized()
	var up := face.cross(right).normalized()
	var yaw := rng.randf_range(-0.6, 0.6)
	var pitch := rng.randf_range(-0.45, 0.45)
	var dir := (face + right * tan(yaw) + up * tan(pitch)).normalized()
	var face_point: Vector3 = centre + dir * radius
	# A little lateral parallax so consecutive kills frame a different patch of
	# cheek/eye/mouth rather than the exact same centre spot.
	var lateral := (right * rng.randf_range(-0.25, 0.25) \
			+ up * rng.randf_range(-0.25, 0.25)) * radius
	var cam_pos: Vector3 = centre + dir * (radius + CATCH_FACE_CLEARANCE) + lateral
	# Hard safety: keep the near plane outside the skull even if a random
	# lateral nudge ever pulls the body of the camera too close.
	var min_dist: float = radius + _feed_cam.near + 0.02
	var off := cam_pos - centre
	if off.length() < min_dist:
		cam_pos = centre + off.normalized() * min_dist
	var cam_up := up
	if absf(dir.dot(cam_up)) > 0.95:
		cam_up = right
	var cam_xform := Transform3D(Basis.IDENTITY, cam_pos).looking_at(face_point, cam_up)
	cam_xform.basis = cam_xform.basis.rotated(cam_xform.basis.z, rng.randf_range(-0.35, 0.35))
	return {
		"host": host,
		"head_centre": centre,
		"head_radius": radius,
		"face_point": face_point,
		"cam_pos": cam_pos,
		"cam_xform": cam_xform,
	}


## Stage the kill close-up on the feed camera (never on `drone.cam`). Returns
## false when the catcher has no resolvable skull, so callers keep old snow.
func _stage_catch_face(host) -> bool:
	var pick := _pick_catch_face(host, _catch_rng)
	if pick.is_empty():
		return false
	last_catch_face = pick
	_catch_cam_active = true
	_catch_frozen = false
	_catch_cam_xform = pick["cam_xform"]
	_catch_cam_fov = CATCH_FACE_FOV
	_catch_hold = CATCH_FACE_HOLD
	_catch_frames = 0
	# The face frames are clean: hold the snow back until the cut.
	_static_lock = 0.0
	_static_boost = 0.0
	hud.set_live_dread(0.2)
	return true


## End the face beat: freeze the last frame, then let the snow take the tube.
## The cut waits for the minimum frame count so a stalled frame cannot skip it.
func _tick_catch_face(delta: float) -> void:
	if not _catch_cam_active:
		return
	_catch_hold -= delta
	if _catch_hold > 0.0 or _catch_frames < CATCH_FACE_MIN_FRAMES:
		return
	_catch_cam_active = false
	_catch_frozen = true
	if _feed_vp != null:
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_static_lock = maxf(_static_lock, 2.2)
	Sfx.play("static", Sfx.CENTER, -6.0)
	hud.set_live_dread(0.0)


func _clear_catch_face() -> void:
	_catch_cam_active = false
	_catch_frozen = false
	last_catch_face = {}


## Toggle the video module's far-focus loss. The photo renderer turns it off
## for its single frame; the live tube turns it on while it is flying.
func _set_video_optics(on: bool) -> void:
	if _feed_attrs == null or _video_optics_on == on:
		return
	_video_optics_on = on
	_feed_attrs.dof_blur_far_enabled = on


func _on_drone_battery_dead(d = null) -> void:
	if _reeling:
		return
	# Only the linked chassis drains, so a parked bot should never fire this.
	# If it somehow does, ignore it: the fleet keeps flying.
	if d != null and d != drone:
		return
	hud.show_message("BATTERY EMPTY", 2.0)
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
	_deploy_cd = 0.0
	_bind_senses(null)
	if crawler != null and is_instance_valid(crawler):
		crawler.abandon()
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
	_clear_catch_face()
	_dock_prompt = false
	_set_zone2_dark(false, 1.0)
	hud.hide_photo()
	_photo_show = 0.0
	_refresh_chair_prompt()
	if _pending_end_card:
		_show_module_loss_card()


## The crash card for losing the video module. Shown at teardown when the
## fleet is gone, or immediately when a surviving chassis carries the run on.
func _show_module_loss_card() -> void:
	_pending_end_card = false
	hud.show_end_card("MODULE LOST", "STILL CAMERA ONLY", "CLICK")


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
