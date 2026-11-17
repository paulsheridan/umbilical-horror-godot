extends Node3D
## Scene-integrity probe: controller wiring, gameplay anchors, pickups and
## actor prefabs. Layout and terrain assertions are deliberately excluded so
## the level can be reshaped without breaking this suite.
##
## Run: godot --headless --path . res://tests/level_scene.tscn

const SHIP_SCENE := preload("res://scenes/level/ship.tscn")
const FAB_SCENE := preload("res://scenes/level/rooms/fab_bay.tscn")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const DRONE_SCENE := preload("res://scenes/actors/drone.tscn")
const PROCESSOR_SCENE := preload("res://scenes/actors/processor.tscn")
const COLLECTOR_SCENE := preload("res://scenes/actors/collector.tscn")
const HOST_SCENE := preload("res://scenes/actors/host.tscn")
const STALKER_SCENE := preload("res://scenes/actors/stalker.tscn")
const CRAWLER_SCENE := preload("res://scenes/actors/crawler.tscn")
const PickupProps := preload("res://src/ship/pickup_props.gd")

const ANCHORS := [
	"Dock", "CameraSite", "Flashlight", "GalleyDoorApproach", "CollectorDeposit",
	"ProcessorPos", "ProcessorPile", "ProcessorDrop",
	"Zone2Threshold", "Zone2Relay", "Zone2Spawn0", "Zone2Spawn1",
	"Zone2Spawn2", "Zone2Spawn3", "CrawlerSetPiece", "CrawlerGrab",
	"CollectorSacrifice", "EngineEntry", "EngineRelay", "EngineStalkerSpawn",
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
	_check(ship.zone2_threshold.distance_to(
			(ship.get_node("Data/Anchors/Zone2Threshold") as Node3D).position) < 0.001,
			"the Deck B threshold resolves from its marker")

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
	_check(ship.galley_door != null and ship.camera_module != null,
			"the galley door and video module resolve by name")
	_check(ship.camera_module.get_node_or_null("PickupModel") != null
			and ship.camera_module.get_node_or_null("PickupIndicator") != null,
			"the video module has a 3D model and a floating pickup marker")
	_check(ship.flashlight_pickup != null
			and ship.flashlight_pickup.get_node_or_null("PickupModel") != null
			and ship.flashlight_pickup.get_node_or_null("PickupIndicator") != null,
			"the flashlight has a 3D model and a floating pickup marker")
	if ship.flashlight_pickup != null:
		var cam_marker := ship.camera_module.get_node("PickupIndicator") as Node3D
		var light_marker := ship.flashlight_pickup.get_node("PickupIndicator") as Node3D
		_check(cam_marker.position.y > 0.4 and light_marker.position.y > 0.4,
				"both pickup markers hover above their pickups")
		# The markers were dimmed by a third to stop them blowing out into a
		# white blob on the grainy feed. Construction and the pulse must agree.
		for pair in [["video module", cam_marker], ["flashlight", light_marker]]:
			var label: String = pair[0]
			var marker: Node3D = pair[1]
			var halo_alpha := ((marker.get_node("Spin/Halo") as MeshInstance3D)
					.material_override as StandardMaterial3D).albedo_color.a
			_check(is_equal_approx(halo_alpha, PickupProps.HALO_ALPHA),
					"the %s marker's halo uses the dimmed alpha" % label)
			_check(is_equal_approx(halo_alpha,
					0.34 * PickupProps.MARKER_BRIGHTNESS),
					"the %s marker's halo alpha is a literal two thirds of 0.34" % label)
			var ring_alpha := ((marker.get_node("HoverRing") as CSGTorus3D)
					.material as StandardMaterial3D).albedo_color.a
			_check(is_equal_approx(ring_alpha,
					0.85 * PickupProps.MARKER_BRIGHTNESS),
					"the %s marker's hover ring is dimmed by two thirds" % label)
			_check(is_equal_approx(
					(marker.get_node("Glow") as OmniLight3D).light_energy,
					PickupProps.MARKER_LAMP_ENERGY),
					"the %s marker's lamp starts at the dimmed energy" % label)
		var max_pulsed_energy := 0.0
		for now in [0.0, 0.35, 0.55, 1.1, 2.0]:
			ship._animate_pickup_fx(now)
			for rec in ship._pickup_fx:
				var lamp = rec["lamp"]
				if lamp != null and is_instance_valid(lamp):
					max_pulsed_energy = maxf(max_pulsed_energy,
							(lamp as OmniLight3D).light_energy)
		_check(max_pulsed_energy <= PickupProps.MARKER_LAMP_ENERGY + 0.001,
				"the pickup glow pulse never exceeds the dimmed base")
	_check(ship.collector_pile != null and ship.processor_pile != null,
			"both feeding piles resolve by name")
	_check(ship.zone2_door != null and not ship.zone2_door_open,
			"the Deck B airlock resolves closed at boot")
	_check(ship.processor_pile.get_child_count() >= 10,
			"the Processor's starter heap is baked into the scene")

	# --- Scene materials --------------------------------------------------
	var material_path := ""
	for node in ship.find_children("*", "CSGShape3D", true, false):
		var mat: Material = (node as CSGShape3D).material
		if mat != null:
			material_path = mat.resource_path
			break
	_check(material_path.begins_with("res://assets/materials/"),
			"geometry references shared palette resources (%s)" % material_path)

	# --- Bay --------------------------------------------------------------
	_check(bay.pilot_chair != null and bay.fabricator != null
			and bay.map_table != null, "bay interactables resolve by name")
	_check(bay.map_surface != null, "the paper map surface resolves by name")
	var start := bay.get_node_or_null("PlayerStart") as Node3D
	_check(start != null, "the bay has a PlayerStart marker")
	if start != null:
		var original_start := start.position
		start.position = original_start + Vector3(0.5, 0.0, 0.5)
		bay._ready()
		_check(bay.player_start.distance_to(start.position) < 0.001,
				"editing PlayerStart moves the player spawn")
		start.position = original_start
		bay._ready()

	# --- Actor prefabs -----------------------------------------------------
	var p = PLAYER_SCENE.instantiate()
	add_child(p)
	_check(p is CharacterBody3D and p.get_node_or_null("Collision") != null,
			"the player prefab owns its body and collision")
	_check(p.get_node_or_null("Head/Cam") is Camera3D and p.cam != null,
			"the player prefab owns its camera")
	_check(p.get_node_or_null("Fill") is OmniLight3D,
			"the player prefab owns its eye fill")

	var d = DRONE_SCENE.instantiate()
	add_child(d)
	_check(d is CharacterBody3D and d.get_node_or_null("Chassis/LED") != null,
			"the drone prefab owns its chassis and status LED")
	_check(d.get_node_or_null("Head/Cam") is Camera3D and d.cam != null,
			"the drone prefab owns its camera")
	_check(d.get_node_or_null("Chassis/TrackL") != null
			and d.get_node_or_null("Chassis/TrackR") != null
			and d.get_node_or_null("Lamp") is OmniLight3D,
			"the drone prefab owns its tracks and emergency lamp")
	_check(d.get_node_or_null("Flashlight/Beam") is SpotLight3D
			and d.flashlight is SpotLight3D
			and d.flashlight.spot_angle <= 25.0,
			"the drone prefab owns a narrow-beam flashlight add-on")
	p.queue_free()
	d.queue_free()

	var pr = PROCESSOR_SCENE.instantiate()
	add_child(pr)
	_check(pr.get_node_or_null("Rig/Jaw") is Node3D and pr._jaw != null,
			"the Processor prefab owns its maw and jaw")
	_check(pr._hands.size() == 2 and pr._arm_pivots.size() == 2,
			"the Processor prefab owns both gaunt arms and hands")
	pr.queue_free()

	var col = COLLECTOR_SCENE.instantiate()
	add_child(col)
	_check(col.get_node_or_null("Rig/Model/Root/Skeleton3D") is Skeleton3D
			and col._skeleton != null,
			"the Collector prefab owns its animated Kenney body")
	_check(col._anim != null and col._anim.has_animation("idle")
			and col._anim.has_animation("walk")
			and col._anim.has_animation("jump"),
			"the Collector prefab owns its idle, walk and jump clips")
	_check(col._look != null and col._look_target != null,
			"the Collector prefab owns its head-tracking rig")
	_check(col._lantern != null and col._sack != null,
			"the Collector prefab owns its lantern and drag sack")
	col.queue_free()

	var h = HOST_SCENE.instantiate()
	add_child(h)
	_check(h.get_node_or_null("Meshes/Model/Root/Skeleton3D") is Skeleton3D
			and h._skeleton != null,
			"the host prefab owns its animated Kenney body")
	_check(h._anim != null and h._anim.has_animation("idle")
			and h._anim.has_animation("walk")
			and h._anim.has_animation("run"),
			"the host prefab owns its idle, walk and run clips")
	_check(h.get_node_or_null("Meshes") is Node3D and h._meshes != null,
			"the host prefab keeps its Meshes sway node")
	_check(h.get_node_or_null("CollisionShape3D") is CollisionShape3D,
			"the host prefab keeps its collision capsule")
	h.queue_free()

	var st = STALKER_SCENE.instantiate()
	add_child(st)
	_check(st.get_node_or_null("Rig/Hips/Torso/Head") is Node3D and st._head != null,
			"the Stalker prefab owns its skeletal rig")
	_check(st._arm_l != null and st._arm_r != null
			and st._leg_l != null and st._leg_r != null,
			"the Stalker prefab owns its limbs")
	st.queue_free()

	var cr = CRAWLER_SCENE.instantiate()
	add_child(cr)
	_check(cr is Node3D and not (cr is PhysicsBody3D),
			"the crawler is a collision-free set piece, not a body")
	_check(cr.get_node_or_null("Rig/Torso") is Node3D
			and cr.get_node_or_null("Rig/Head") is Node3D,
			"the crawler prefab owns its torso and head")
	_check(cr.get_node_or_null("Rig/ArmL") is Node3D
			and cr.get_node_or_null("Rig/ArmR") is Node3D,
			"the crawler prefab drags itself with two arms")
	_check(cr.get_node_or_null("Rig/AlienArm") is Node3D,
			"the crawler prefab carries its authored yank arm")
	_check(cr.get_node_or_null("Rig/LegL") == null
			and cr.get_node_or_null("Rig/LegR") == null,
			"the crawler has no legs")
	cr.queue_free()

	print("LEVEL SCENE %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
