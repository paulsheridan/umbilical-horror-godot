extends Node
## Bake parity check: rebuild the legacy geometry and compare it against the
## baked scene. Compares class, world transform, primitive size and material
## for every renderable/collision node, in traversal order.
##
## Run: godot --headless --path . res://tools/verify_bake.tscn

const BUILDER := preload("res://tools/legacy/beyond_builder.gd")
const SHIP_SCENE := preload("res://scenes/level/ship.tscn")

const EPS := 0.001

var _root_built: Node
var _root_baked: Node


func _ready() -> void:
	var built = BUILDER.new()
	_root_built = built
	add_child(built)
	built.build()
	var baked = SHIP_SCENE.instantiate()
	_root_baked = baked
	add_child(baked)
	await get_tree().process_frame

	var a: Array = []
	var b: Array = []
	_collect(built, a)
	_collect(baked, b)

	var bad := 0
	if a.size() != b.size():
		print("COUNT MISMATCH: builder=%d baked=%d" % [a.size(), b.size()])
		bad += 1
	var n := mini(a.size(), b.size())
	for i in n:
		var d: String = _diff(a[i], b[i])
		if d != "":
			bad += 1
			if bad <= 20:
				print("DIFF %d: %s" % [i, d])
	print("PARITY %s (%d nodes compared, %d differences)"
			% ["PASS" if bad == 0 else "FAIL", n, bad])
	get_tree().quit(0 if bad == 0 else 1)


func _collect(node: Node, out: Array) -> void:
	if node is CSGShape3D or node is OmniLight3D or node is StaticBody3D \
			or node is CollisionShape3D or node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


func _diff(x: Node, y: Node) -> String:
	# Remains are deliberately randomised at build time; their parent rotation
	# and the child offsets are the only non-deterministic geometry.
	if _under_remains(x, _root_built) or _under_remains(y, _root_baked):
		return ""
	var label := "%s vs %s" % [x.get_class(), y.get_class()]
	if x.get_class() != y.get_class():
		return "%s: class" % label
	if not _same_vec(x.global_position, y.global_position):
		return "%s: pos %s vs %s" % [label, x.global_position, y.global_position]
	if not _same_vec(x.global_rotation, y.global_rotation):
		return "%s: rot %s vs %s" % [label, x.global_rotation, y.global_rotation]
	if x is CSGBox3D and not _same_vec((x as CSGBox3D).size, (y as CSGBox3D).size):
		return "%s: size %s vs %s" % [label, (x as CSGBox3D).size, (y as CSGBox3D).size]
	if x is CSGCylinder3D:
		var cx := x as CSGCylinder3D
		var cy := y as CSGCylinder3D
		if absf(cx.radius - cy.radius) > EPS or absf(cx.height - cy.height) > EPS:
			return "%s: cyl r/h" % label
	if x is CSGSphere3D and absf((x as CSGSphere3D).radius - (y as CSGSphere3D).radius) > EPS:
		return "%s: sphere radius" % label
	if x is CSGShape3D:
		var mx: Material = (x as CSGShape3D).material
		var my: Material = (y as CSGShape3D).material
		if mx != null and my != null and mx.resource_path != my.resource_path:
			return "%s: material %s vs %s" % [label, mx.resource_path, my.resource_path]
		if (x as CSGShape3D).use_collision != (y as CSGShape3D).use_collision:
			return "%s: collision flag" % label
	if x is CollisionShape3D:
		var sx := (x as CollisionShape3D).shape
		var sy := (y as CollisionShape3D).shape
		if sx is BoxShape3D and sy is BoxShape3D:
			if not _same_vec((sx as BoxShape3D).size, (sy as BoxShape3D).size):
				return "%s: box shape" % label
	if x is OmniLight3D:
		if (x as OmniLight3D).light_color != (y as OmniLight3D).light_color:
			return "%s: light color" % label
		if absf((x as OmniLight3D).light_energy - (y as OmniLight3D).light_energy) > EPS:
			return "%s: light energy" % label
	return ""


func _under_remains(node: Node, root: Node) -> bool:
	var parent := node.get_parent()
	return parent != null and parent != root and parent.get_child_count() == 3 \
			and parent.get_parent() == root and not parent is CSGShape3D


func _same_vec(p: Vector3, q: Vector3) -> bool:
	return p.distance_to(q) <= EPS
