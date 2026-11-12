extends Node
## One-time migration: run the two procedural builders, tag the gameplay data
## they create, and save the result as editable scenes.
##
## Run: godot --headless --path . res://tools/bake_level.tscn
## Re-run only while the builders still exist; after the refactor the .tscn
## files are the source of truth.

const FAB_BAY := preload("res://tools/legacy/fab_bay_builder.gd")
const BEYOND := preload("res://tools/legacy/beyond_builder.gd")

const FAB_PATH := "res://scenes/level/rooms/fab_bay.tscn"
const SHIP_PATH := "res://scenes/level/ship.tscn"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://scenes/level/rooms"))
	_bake_fab()
	_bake_ship()
	get_tree().quit()


func _bake_fab() -> void:
	var root = FAB_BAY.new()
	root.name = "FabBay"
	add_child(root)
	root.build()

	# Named references survive the bake; the controller resolves them by name.
	root.pilot_chair.name = "PilotChair"
	root.fabricator.name = "Fabricator"
	root.map_table.name = "MapTable"
	root.map_surface.name = "MapSurface"
	root._flicker.name = "MapFlicker"
	root._emergency.name = "EmergencyLight"

	# The scene root must point at the runtime controller, not the migration
	# builder, or every load would try to rebuild the room.
	root.set_script(load("res://src/hub/fab_bay.gd"))

	_own(root, root)
	_save(root, FAB_PATH)
	root.queue_free()


func _bake_ship() -> void:
	var root = BEYOND.new()
	root.name = "Ship"
	add_child(root)
	root.build()

	# Fixed nodes the controller and gameplay look up by name.
	root.galley_door.name = "GalleyDoor"
	root.camera_module.name = "CameraModule"
	root.collector_pile.name = "CollectorPile"
	root.processor_pile.name = "ProcessorPile"
	if root.has_meta("door_lamp"):
		var lamp = root.get_meta("door_lamp")
		if lamp != null:
			lamp.name = "DoorLamp"
	if root.has_meta("flicker"):
		var flicker = root.get_meta("flicker")
		if flicker != null:
			flicker.name = "FlickerLight"
	# Object-valued metadata does not survive packing as a reference; the
	# controller resolves these by node name instead.
	root.remove_meta("door_lamp")
	root.remove_meta("flicker")

	# Loud doors: keep the panel node, store the open/trigger vectors as
	# metadata so the controller can rebuild its runtime dictionaries.
	for i in root.loud_doors.size():
		var d: Dictionary = root.loud_doors[i]
		var panel: Node3D = d["node"]
		panel.name = "LoudDoor%d" % i
		panel.add_to_group("loud_door")
		panel.set_meta("kind", "loud_door")
		panel.set_meta("door_open", d["open"])
		panel.set_meta("door_trigger", d["trigger"])

	# Remains: the nodes already exist; the controller rebuilds the list.
	for i in root.remains.size():
		var r: Dictionary = root.remains[i]
		var node: Node3D = r["node"]
		node.name = "Remains%d" % i
		node.add_to_group("remains")
		node.set_meta("kind", "remains")

	# Data-only footprints have no node of their own. Bake them as markers so
	# they are visible and movable in the editor.
	var data := Node3D.new()
	data.name = "Data"
	root.add_child(data)

	for i in root.hide_spots.size():
		var spot: Dictionary = root.hide_spots[i]
		var m := Marker3D.new()
		m.name = "HideSpot%d" % i
		m.position = spot["center"]
		m.set_meta("kind", "hide_spot")
		m.set_meta("half", spot["half"])
		m.add_to_group("hide_spot")
		data.add_child(m)

	for i in root.ambush_spots.size():
		var m := Marker3D.new()
		m.name = "AmbushSpot%d" % i
		m.position = root.ambush_spots[i]
		m.set_meta("kind", "ambush_spot")
		m.add_to_group("ambush_spot")
		data.add_child(m)

	for i in root.chokes.size():
		var c: Dictionary = root.chokes[i]
		var m := Marker3D.new()
		m.name = "Choke%d" % i
		m.position = c["center"]
		m.set_meta("kind", "choke")
		m.set_meta("half", c["half"])
		m.set_meta("north", c["north"])
		m.set_meta("south", c["south"])
		m.add_to_group("choke")
		data.add_child(m)

	# Swap the migration builder for the runtime controller before packing.
	root.set_script(load("res://src/ship/beyond.gd"))

	_own(root, root)
	_save(root, SHIP_PATH)
	root.queue_free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("bake: pack failed for %s (%d)" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("bake: save failed for %s (%d)" % [path, err])
		return
	print("baked %-42s %d nodes" % [path, _count(root)])


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
