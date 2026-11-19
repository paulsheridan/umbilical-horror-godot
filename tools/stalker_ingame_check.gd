extends Node
## In-game diagnostic: boots the REAL game (main.tscn, autoloads, PSX screen),
## walks the player to the engine-room lair corner, captures the composited
## picture and dumps every piece of state that could make the Stalker invisible.
##
## Run (windowed tool, not headless — it captures the real screen):
##   env -u WAYLAND_DISPLAY DISPLAY=:1 godot --path . --resolution 960x540 \
##       --audio-driver Dummy tools/stalker_ingame_check.tscn
##
## It prints one fact per line and writes /tmp/opencode/ingame_*.png, then quits.
## Boot order mirrors tests/autotest.gd so the game is in exactly the state a
## player's session is in (PSXLook bound, materials converted, HUD started).
##
## It answers, in order: is the body spawned and on the floor; is its rig built,
## visible and converted; is the PSX pipeline in a sane state; is the body in the
## same World3D and in front of the viewport camera; does anything solid stand
## between the room and the lair (a 16-point ray ring); and what does the
## composited picture actually contain (luma stats per capture).

const OUT_DIR := "/tmp/opencode"
const MAIN_SCENE := "res://scenes/main.tscn"
## The two vantages used for the pictures (metres on the engine-room floor).
## They look at the LIVE body, not at a baked constant, so moving the authored
## lair marker cannot silently point this tool at empty floor.
const FAR_VIEW := Vector3(27.0, 0.05, -81.0)
## Backed off 1.5x from the old (29.4, 0.05, -85.4) along the same floor line
## of sight to the lair marker (28.66, 0.2, -87.12): the body grew 1.5x and the
## old vantage cropped the folded tail off the bottom of ingame_close.png.
const CLOSE_VIEW := Vector3(29.77, 0.05, -84.54)
const NORTH_VIEW := Vector3(26.0, 0.05, -88.0)
## The authored Head node height above the player body origin.
const EYE_HEIGHT := 1.62

var main: Node3D = null
var _height_zombie = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	PSXLook.reset_to_defaults(false)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s" % MAIN_SCENE)
		get_tree().quit()
		return
	main = packed.instantiate() as Node3D
	add_child(main)
	await _frames(6)
	main._on_start_clicked.call_deferred()
	await _frames(12)
	# begin_game() fades the title veil over 1.1 s. Capturing through it would
	# photograph the menu, not the room (it is what spoiled the first run).
	for _i in 150:
		if main.hud._title == null or not main.hud._title.visible:
			break
		await get_tree().physics_frame
	print("title veil hidden=%s" % str(
			main.hud._title == null or not main.hud._title.visible))

	_line()
	print("== BOOT STATE ==")
	print("player (bay start)   %s" % str(main.player.global_position))

	# ---- Height comparison the player asked for -------------------------
	_height_zombie = main._host(Vector3(21.0, 0.2, -75.0),
			[Vector3(21.0, 0.0, -75.0)])
	await _frames(8)

	_line()
	print("== HEIGHT / PLACEMENT ==")
	_dump_stalker_placement()
	print("zombie(engine room)  y=%.3f  pos=%s" % [
			_height_zombie.global_position.y,
			str(_height_zombie.global_position)])
	print("player.bay start     y=%.3f" % main.player.global_position.y)

	# ---- Rig census -----------------------------------------------------
	_line()
	print("== RIG CENSUS (main.stalker) ==")
	_dump_census(main.stalker)

	# ---- Rig transform / NaN check --------------------------------------
	_line()
	print("== RIG TRANSFORM ==")
	_dump_rig()

	# ---- PSXLook state ---------------------------------------------------
	_line()
	print("== PSXLOOK STATE ==")
	_dump_psx()

	# ---- World identity / lights ----------------------------------------
	_line()
	print("== WORLD / LIGHTS ==")
	_dump_world()

	# ---- Can the room see the lair at all? ------------------------------
	_line()
	print("== LAIR SIGHTLINES (is the folded body behind geometry?) ==")
	_dump_sightlines()

	# ---- Captures --------------------------------------------------------
	_line()
	print("== CAPTURES ==")
	var lair: Vector3 = main.stalker.global_position
	var aim: Vector3 = lair + Vector3(0, 0.35, 0)
	var far: Vector3 = FAR_VIEW
	_look_at(far, aim)
	await _frames(12)
	_occlusion("far")
	await _shoot("far")

	var close: Vector3 = CLOSE_VIEW
	_look_at(close, aim)
	await _frames(12)
	_occlusion("close")
	await _shoot("close")

	# Extra vantage: the relay-room mouth to the north-west. Included so the
	# verdict can say from where in the room the folded body can be seen.
	var north: Vector3 = NORTH_VIEW
	_look_at(north, aim)
	await _frames(12)
	_occlusion("north")
	await _shoot("north")

	# The real F4 path (main._input reads the raw F4 key and calls this).
	main._toggle_debug_vision()
	print("debug_vision=%s  PSXLook.debug_suspended()=%s" % [
			str(main.debug_vision), str(PSXLook.debug_suspended())])
	_look_at(close, aim)
	await _frames(12)
	_occlusion("debug")
	await _shoot("debug")

	# Beeline: stand next to the folded body and look straight down.
	var beeline: Vector3 = main.stalker.global_position + Vector3(0.0, 0.9, 1.2)
	_place(beeline, 0.0, -1.2)
	await _frames(12)
	_occlusion("beeline")
	print("beeline player=%s  cam=%s  pitch=%.2f" % [
			str(main.player.global_position),
			str(main.player.cam.global_position), main.player._pitch])
	await _shoot("lair_beeline")

	# ---- Pixel analysis --------------------------------------------------
	_line()
	print("== PIXELS ==")
	for shot in ["far", "close", "north", "debug", "lair_beeline"]:
		_report_pixels(shot)

	get_tree().quit()


# --------------------------------------------------------------------------
# Dumps
# --------------------------------------------------------------------------

func _dump_stalker_placement() -> void:
	var s = main.stalker
	if s == null or not is_instance_valid(s):
		print("stalker INVALID / MISSING")
		return
	print("stalker              y=%.3f  pos=%s" % [s.global_position.y,
			str(s.global_position)])
	print("stalker.state=%d  _on_wall=%s  visible=%s  in_tree_visible=%s" % [
			int(s.state), str(s._on_wall), str(s.visible),
			str(s.is_visible_in_tree())])
	print("stalker global_scale=%s  yaw=%.3f" % [
			str(s.global_transform.basis.get_scale()), s.rotation.y])
	print("stalker spawn mark   %s" % str(main.ship.engine_stalker_spawn))
	print("distance body->mark  %.3f m" % s.global_position.distance_to(
			main.ship.engine_stalker_spawn))
	print("ambush target        %s  _ambush_t=%.2f" % [
			str(s._ambush_target), s._ambush_t])
	print("drone bound          %s" % str(s.drone))
	print("floor contact        is_on_floor=%s  velocity.y=%.3f" % [
			str(s.is_on_floor()), s.velocity.y])
	# Ground query under the body, so "floating / sunk / no collider" is provable.
	var space: PhysicsDirectSpaceState3D = s.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			s.global_position + Vector3(0, 1.0, 0),
			s.global_position + Vector3(0, -2.0, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("ground under body    NONE (no collider below)")
	else:
		print("ground under body    y=%.3f  %s" % [
				float(hit["position"].y), str(hit["collider"])])


func _dump_census(root: Node) -> void:
	var acc := {
		"total": 0, "csg": 0, "mesh": 0,
		"hidden_direct": [], "hidden_in_tree": 0,
		"override_null": 0, "override_shader": 0, "override_raw": 0,
		"effective_raw": 0, "no_material": 0,
	}
	_census_walk(root, root, acc)
	print("total nodes under stalker        %d" % acc.total)
	print("CSGShape3D                        %d" % acc.csg)
	print("MeshInstance3D                    %d" % acc.mesh)
	print("visible=false (direct)            %d" % acc.hidden_direct.size())
	for p: String in acc.hidden_direct:
		print("    HIDDEN  %s" % p)
	print("not visible in tree (CSG+mesh)    %d" % acc.hidden_in_tree)
	print("material_override == null         %d" % acc.override_null)
	print("material_override is ShaderMat    %d" % acc.override_shader)
	print("material_override is BaseMat3D    %d" % acc.override_raw)
	print("effective raw BaseMaterial3D      %d" % acc.effective_raw)
	print("no material at all (renders white)%d" % acc.no_material)


func _census_walk(node: Node, root: Node, acc: Dictionary) -> void:
	acc.total += 1
	if not node.visible:
		var p: String = "." if node == root else String(root.get_path_to(node))
		acc.hidden_direct.append(p)
	var geom := node is CSGShape3D or node is MeshInstance3D
	if node is CSGShape3D:
		acc.csg += 1
	if node is MeshInstance3D:
		acc.mesh += 1
	if geom:
		if not node.is_visible_in_tree():
			acc.hidden_in_tree += 1
		var override: Material = null
		if node is GeometryInstance3D:
			override = node.material_override
		if override == null:
			acc.override_null += 1
		elif override is ShaderMaterial:
			acc.override_shader += 1
		elif override is BaseMaterial3D:
			acc.override_raw += 1
		var raw: Material = override
		if raw == null and node is CSGPrimitive3D:
			raw = node.material
		if raw == null:
			acc.no_material += 1
		elif raw is BaseMaterial3D:
			acc.effective_raw += 1
	for child in node.get_children():
		_census_walk(child, root, acc)


func _dump_rig() -> void:
	var s = main.stalker
	var rig: Node3D = s.get_node_or_null("Rig")
	if rig == null:
		print("Rig MISSING (rig never built)")
		return
	var b: Basis = rig.global_basis
	var p: Vector3 = rig.global_position
	var body: Vector3 = s.global_position
	var nan_basis: bool = is_nan(b.x.x) or is_nan(b.x.y) or is_nan(b.x.z) \
			or is_nan(b.y.x) or is_nan(b.y.y) or is_nan(b.y.z) \
			or is_nan(b.z.x) or is_nan(b.z.y) or is_nan(b.z.z) \
			or is_nan(p.x) or is_nan(p.y) or is_nan(p.z)
	print("Rig children           %d" % rig.get_child_count())
	print("Rig global_position    %s" % str(p))
	print("Rig offset from body   %s" % str(p - body))
	print("Rig global_basis.x     (%.3f, %.3f, %.3f)" % [b.x.x, b.x.y, b.x.z])
	print("Rig global_basis.y     (%.3f, %.3f, %.3f)" % [b.y.x, b.y.y, b.y.z])
	print("Rig global_basis.z     (%.3f, %.3f, %.3f)" % [b.z.x, b.z.y, b.z.z])
	print("Rig scale              %s" % str(rig.scale))
	print("Rig NaN                %s" % str(nan_basis))
	var head: Node3D = rig.get_node_or_null("Head")
	if head != null:
		print("Rig/Head global_pos    %s" % str(head.global_position))
		print("Rig/Head visible       %s" % str(head.is_visible_in_tree()))
	else:
		print("Rig/Head MISSING")
	var seg: Node3D = rig.get_node_or_null("Seg0")
	if seg != null:
		print("Rig/Seg0 global_pos    %s" % str(seg.global_position))
	print("Rig origin to head     %.3f m" % (
			head.global_position.distance_to(p) if head != null else -1.0))


func _dump_psx() -> void:
	print("master=%s conversion=%s density=%.2f debug=%s" % [
			str(PSXLook.master), str(PSXLook.conversion), PSXLook.density,
			str(PSXLook.debug_suspended())])
	print("fog=%s fog_begin=%.1f fog_end=%.1f" % [
			str(PSXLook.fog), PSXLook.fog_begin, PSXLook.fog_end])
	print("draw_distance_on=%s draw_distance=%.1f" % [
			str(PSXLook.draw_distance_on), PSXLook.draw_distance])
	print("categories glow=%s cutout=%s transparent=%s sprites=%s" % [
			str(PSXLook.glow), str(PSXLook.cutout), str(PSXLook.transparent),
			str(PSXLook.sprites)])
	print("_zone_dark=%.3f" % PSXLook._zone_dark)
	var vp: SubViewport = PSXLook.viewport
	if vp == null:
		print("PSXLook.viewport NULL")
		return
	print("viewport.size=%s own_world_3d=%s" % [
			str(vp.size), str(vp.own_world_3d)])
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		print("viewport camera NULL (nothing renders the 3D)")
	else:
		print("viewport camera=%s near=%.3f far=%.1f fov=%.1f current=%s" % [
				String(cam.get_path()), cam.near, cam.far, cam.fov,
				str(cam.is_current())])
		print("camera global_pos      %s" % str(cam.global_position))
	# Category records that cover the stalker.
	var s = main.stalker
	var cat_n := 0
	var cat_list: Array = []
	for id in PSXLook._category_nodes.keys():
		var rec: Dictionary = PSXLook._category_nodes[id]
		var n = rec.get("node")
		if n == null or not is_instance_valid(n):
			continue
		if n == s or (s != null and is_instance_valid(s) and s.is_ancestor_of(n)):
			cat_n += 1
			cat_list.append("%s:%s(vis=%s)" % [
					String(s.get_path_to(n)), str(rec["categories"]),
					str(n.visible)])
	print("category records on stalker  %d" % cat_n)
	for c: String in cat_list:
		print("    CAT  %s" % c)
	# Conversion coverage.
	var ent_n := 0
	for e: Dictionary in PSXLook._entries:
		var n = e.get("node")
		if n == null or not is_instance_valid(n):
			continue
		if n == s or (s != null and is_instance_valid(s) and s.is_ancestor_of(n)):
			ent_n += 1
	print("_entries covering stalker    %d  (of %d total)" % [
			ent_n, PSXLook._entries.size()])
	print("_cache materials             %d" % PSXLook._cache.size())


func _dump_world() -> void:
	var s = main.stalker
	var sw: World3D = s.get_world_3d()
	var pw: World3D = main.player.get_world_3d()
	var vw: World3D = PSXLook.world_3d()
	print("stalker world==player world  %s" % str(sw == pw))
	print("stalker world==PSX world     %s" % str(sw == vw))
	print("stalker world rid            %s" % str(sw.get_rid()))
	print("player world rid             %s" % str(pw.get_rid()))
	print("portal_path?                 %s" % str(sw.get_scenario()))
	print("environment ambient=%s fog=%s exposure=%.2f" % [
			str(main._env.ambient_light_energy) if main._env != null else "null",
			str(main._env.fog_enabled) if main._env != null else "null",
			main._env.tonemap_exposure if main._env != null else 0.0])
	var lights := 0
	var near: Array = []
	for n in main.world.find_children("*", "Light3D", true, false):
		var lp: Vector3 = (n as Node3D).global_position
		var d := lp.distance_to(s.global_position)
		if d < 12.0:
			lights += 1
			if near.size() < 6:
				var l := n as Light3D
				near.append("%s d=%.1f e=%.2f%s" % [n.name, d, l.light_energy,
						"" if n.is_visible_in_tree() else " HIDDEN"])
	print("lights within 12 m of stalker  %d" % lights)
	for t: String in near:
		print("    LIGHT  %s" % t)


## Can the room see the lair at all? A 16-point ring at eye height around the
## folded body, plus a point query inside the body's own volume: proves whether
## the corner is open floor or a pocket walled in by the level geometry.
func _dump_sightlines() -> void:
	var s = main.stalker
	var head: Vector3 = s.get_node("Rig").get_node("Head").global_position
	var space: PhysicsDirectSpaceState3D = s.get_world_3d().direct_space_state
	for y: float in [0.3, 0.7, 1.1]:
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = s.global_position + Vector3(0, y, 0)
		pq.collision_mask = 1
		var inside := space.intersect_point(pq)
		print("point query at lair y=%.1f  solids=%d%s" % [y, inside.size(),
				"" if inside.is_empty() else "  " + str(inside[0]["collider"])])
	var clear := 0
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var from: Vector3 = s.global_position + Vector3(sin(ang), 0.0, cos(ang)) * 5.0
		from.y = 1.62
		var q := PhysicsRayQueryParameters3D.create(from, head)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			clear += 1
		else:
			print("    ring %2d (%5.1f,%5.1f)  BLOCKED %.2f m by %s" % [
					i, from.x, from.z,
					from.distance_to(hit["position"]),
					str((hit["collider"] as Node).name)])
	print("ring of 16 vantages at 5 m: %d clear, %d blocked" % [clear, 16 - clear])


## One ray from the live viewport camera to the stalker's head: proves whether
## the body is in frame and what, if anything, is between the two.
func _occlusion(tag: String) -> void:
	var s = main.stalker
	var cam: Camera3D = PSXLook.current_camera()
	if cam == null or s == null or not is_instance_valid(s):
		print("[%s] occlusion: no camera/stalker" % tag)
		return
	var head: Vector3 = s.get_node("Rig").get_node("Head").global_position
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position + Vector3(0, 0.05, 0), head)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	print("[%s] cam=%s  head=%s  dist=%.2f  in_frustum=%s" % [
			tag, str(cam.global_position), str(head),
			cam.global_position.distance_to(head),
			str(cam.is_position_in_frustum(head))])
	if hit.is_empty():
		print("[%s] ray to head CLEAR (no world collider between)" % tag)
	else:
		print("[%s] ray to head BLOCKED at %.2f m by %s" % [
				tag, cam.global_position.distance_to(hit["position"]),
				str(hit["collider"])])
	print("[%s] stalker in frustum=%s  aabb?  dist=%.2f" % [
			tag, str(cam.is_position_in_frustum(s.global_position)),
			cam.global_position.distance_to(s.global_position)])


# --------------------------------------------------------------------------
# Capture
# --------------------------------------------------------------------------

## Stand the player at `pos` and aim the eye (1.62 m above the body origin, the
## authored Head height) at `target`. Pitch is solved, not baked: a fixed -0.05
## frames a 6 m body at eye level and misses a 0.3 m folded one at your feet.
func _look_at(pos: Vector3, target: Vector3) -> void:
	var flat := Vector2(target.x - pos.x, target.z - pos.z)
	var yaw := atan2(-flat.x, -flat.y)
	var pitch := atan2(target.y - (pos.y + EYE_HEIGHT), flat.length())
	_place(pos, yaw, pitch)


func _place(pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.player.velocity = Vector3.ZERO
	main.player.rotation.y = yaw
	main.player._pitch = pitch
	main.player.cam.rotation.x = pitch


func _shoot(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/ingame_%s.png" % [OUT_DIR, shot]
	var err := img.save_png(path)
	if err != OK:
		push_error("could not save %s (error %d)" % [path, err])
		return
	print("saved %s  %dx%d  %d bytes" % [path, img.get_width(), img.get_height(),
			FileAccess.get_file_as_bytes(path).size()])


# --------------------------------------------------------------------------
# Pixel analysis (same luminance approach as /tmp/opencode/pixel_check.gd)
# --------------------------------------------------------------------------

func _report_pixels(shot: String) -> void:
	var path := "%s/ingame_%s.png" % [OUT_DIR, shot]
	var img := Image.load_from_file(path)
	if img == null:
		print("%-16s LOAD FAILED (%s)" % [shot, path])
		return
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	var lo := 999.0
	var hi := -1.0
	var sum := 0.0
	var a45 := 0
	var a110 := 0
	# Central 50% (the close-vantage corner body band).
	var bx0 := int(w * 0.25)
	var bx1 := int(w * 0.75)
	var by0 := int(h * 0.25)
	var by1 := int(h * 0.75)
	# Upper-middle (where a 6 m body sits with a level camera).
	var uy0 := int(h * 0.20)
	var uy1 := int(h * 0.65)
	var band_n := 0
	var band_45 := 0
	var band_sum := 0.0
	var upper_n := 0
	var upper_45 := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			lo = minf(lo, l)
			hi = maxf(hi, l)
			sum += l
			n += 1
			if l > 45.0:
				a45 += 1
			if l > 110.0:
				a110 += 1
			if x >= bx0 and x < bx1 and y >= by0 and y < by1:
				band_n += 1
				band_sum += l
				if l > 45.0:
					band_45 += 1
			if x >= bx0 and x < bx1 and y >= uy0 and y < uy1:
				upper_n += 1
				if l > 45.0:
					upper_45 += 1
	print("%-14s %dx%d min=%.1f mean=%.1f max=%.1f  >45=%d (%.2f%%)  >110=%d (%.2f%%)" % [
			shot, w, h, lo, sum / float(n), hi, a45, 100.0 * a45 / float(n),
			a110, 100.0 * a110 / float(n)])
	print("    band(central 50%%)  px=%d >45=%d (%.2f%%) mean=%.1f" % [
			band_n, band_45, 100.0 * band_45 / float(band_n),
			band_sum / float(band_n)])
	print("    band(upper-mid)    px=%d >45=%d (%.2f%%)" % [
			upper_n, upper_45, 100.0 * upper_45 / float(upper_n)])


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _line() -> void:
	print("------------------------------------------------------------------")
