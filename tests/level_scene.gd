extends Node3D
## Scene-integrity probe: the baked level must stay the source of truth.
## Verifies the controller wiring, anchors, baked data lists, shared material
## assets and the room grouping that makes the scene editable.
##
## Run: godot --headless --path . res://tests/level_scene.tscn

const SHIP_SCENE := preload("res://scenes/level/ship.tscn")
const FAB_SCENE := preload("res://scenes/level/rooms/fab_bay.tscn")

const ANCHORS := [
	"Dock", "CameraSite", "Food", "GalleyDoorApproach", "CollectorDeposit",
	"ProcessorPos", "ProcessorPile", "ProcessorDrop",
]
const ROOMS := [
	"Corridor", "Junction", "Spur", "Galley", "Annex", "BerthWing",
	"ProcessorWing", "World",
]

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failed = true


func _run() -> void:
	var ship = SHIP_SCENE.instantiate()
	add_child(ship)
	var bay = FAB_SCENE.instantiate()
	add_child(bay)
	await get_tree().physics_frame

	# --- Controllers, not builders ----------------------------------------
	_check(ship.has_method("_scan_data") and not ship.has_method("build"),
			"the ship root runs the controller, not the migration builder")
	_check(bay.has_method("_process") and not bay.has_method("build"),
			"the bay root runs the controller, not the migration builder")

	# --- Anchors -----------------------------------------------------------
	var missing := []
	for anchor in ANCHORS:
		if ship.get_node_or_null("Data/Anchors/%s" % anchor) == null:
			missing.append(anchor)
	_check(missing.is_empty(), "all gameplay anchors exist (%s)" % str(missing))
	_check(ship.dock_pos.distance_to(
			(ship.get_node("Data/Anchors/Dock") as Node3D).position) < 0.001,
			"dock placement resolves from its marker")
	_check(ship.PROCESSOR_PILE.distance_to(
			(ship.get_node("Data/Anchors/ProcessorPile") as Node3D).position) < 0.001,
			"the Processor pile resolves from its marker")

	# Moving a marker and re-resolving must move gameplay.
	var pile_marker := ship.get_node("Data/Anchors/ProcessorPile") as Node3D
	var original: Vector3 = pile_marker.position
	pile_marker.position = original + Vector3(0.0, 0.0, -0.6)
	ship._ready()
	_check(ship.PROCESSOR_PILE.distance_to(pile_marker.position) < 0.001,
			"editing the pile marker changes the gameplay pile")
	pile_marker.position = original
	ship._ready()

	# --- Baked gameplay data ----------------------------------------------
	_check(ship.hide_spots.size() == 6, "six low-table/bunk hide spots")
	_check(ship.ambush_spots.size() == 11, "eleven stalker ambush spots")
	_check(ship.chokes.size() == 2, "two body-height chokes")
	_check(ship.loud_doors.size() == 4, "four loud cabin doors")
	_check(ship.remains.size() == 12, "twelve scattered remains")
	_check(ship.galley_door != null and ship.camera_module != null,
			"the galley door and video module resolve by name")
	_check(ship.collector_pile != null and ship.processor_pile != null,
			"both feeding piles resolve by name")
	_check(ship.processor_pile.get_child_count() >= 10,
			"the Processor's starter heap is baked into the scene")

	# --- Scene shape / materials ------------------------------------------
	var rooms_found := 0
	var chars := 0
	for child in ship.get_children():
		if child.name in ROOMS:
			rooms_found += 1
			chars += _count(child)
	_check(rooms_found == ROOMS.size(), "all eight room containers exist")
	_check(chars >= 330, "room containers hold the geometry (%d nodes)" % chars)

	var material_path := ""
	for node in ship.find_children("*", "CSGShape3D", true, false):
		var mat: Material = (node as CSGShape3D).material
		if mat != null:
			material_path = mat.resource_path
			break
	_check(material_path.begins_with("res://assets/materials/"),
			"geometry references shared palette resources (%s)" % material_path)

	var floor_shape := ""
	for node in ship.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.get_child_count() > 0 and body.get_child(0) is CollisionShape3D:
			var shape := (body.get_child(0) as CollisionShape3D).shape
			if shape is BoxShape3D:
				floor_shape = str((shape as BoxShape3D).size)
	_check(floor_shape == str(Vector3(56.0, 0.5, 31.0)),
			"the single flat floor collider survived the bake")

	# --- Bay --------------------------------------------------------------
	_check(bay.pilot_chair != null and bay.fabricator != null
			and bay.map_table != null, "bay interactables resolve by name")
	_check(bay.map_surface != null, "the paper map surface resolves by name")
	var start := bay.get_node_or_null("PlayerStart") as Node3D
	_check(start != null, "the bay has a PlayerStart marker")
	if start != null:
		start.position = Vector3(1.0, 0.2, 1.5)
		bay._ready()
		_check(bay.player_start.distance_to(start.position) < 0.001,
				"editing PlayerStart moves the player spawn")
		start.position = Vector3(4.8, 0.2, 2.8)
		bay._ready()

	print("LEVEL SCENE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
