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
	_collect(built, a, built)
	_collect(baked, b, baked)

	# Order-independent comparison: room grouping moves nodes between parents,
	# so compare the multiset of signatures instead of traversal order.
	var ca := {}
	for n in a:
		var k := _sort_key(n)
		ca[k] = int(ca.get(k, 0)) + 1
	var cb := {}
	for n in b:
		var k := _sort_key(n)
		cb[k] = int(cb.get(k, 0)) + 1

	var bad := 0
	for k in ca:
		if int(ca[k]) != int(cb.get(k, 0)):
			bad += 1
			if bad <= 20:
				print("DIFF: %s (builder %d, baked %d)"
						% [k, ca[k], cb.get(k, 0)])
	for k in cb:
		if not ca.has(k):
			bad += 1
			if bad <= 20:
				print("EXTRA: %s (baked only, x%d)" % [k, cb[k]])
	print("PARITY %s (%d nodes compared, %d differences)"
			% ["PASS" if bad == 0 else "FAIL", mini(a.size(), b.size()), bad])
	get_tree().quit(0 if bad == 0 else 1)


func _sort_key(n: Node) -> String:
	var extra := ""
	if n is CSGBox3D:
		extra = str((n as CSGBox3D).size)
	elif n is CSGCylinder3D:
		extra = "%.3f/%.3f" % [(n as CSGCylinder3D).radius, (n as CSGCylinder3D).height]
	elif n is CSGSphere3D:
		extra = "%.3f" % (n as CSGSphere3D).radius
	elif n is OmniLight3D:
		extra = str((n as OmniLight3D).light_color)
	return "%s|%.3f|%.3f|%.3f|%s" % [n.get_class(), n.global_position.x,
			n.global_position.y, n.global_position.z, extra]


func _collect(node: Node, out: Array, root: Node) -> void:
	if _under_remains(node, root):
		return
	if node is CSGShape3D or node is OmniLight3D or node is StaticBody3D \
			or node is CollisionShape3D or node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out, root)


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


func _under_remains(node: Node, _root: Node) -> bool:
	# Remains are a 3-child cluster (long bone, wet mass, skull chip). Their
	# rotation is randomised per build, so they are excluded from parity.
	var parent := node.get_parent()
	if parent == null or parent.get_child_count() != 3:
		return false
	var first := parent.get_child(0)
	return first is CSGBox3D \
			and (first as CSGBox3D).size.is_equal_approx(Vector3(0.08, 0.07, 0.46))


func _same_vec(p: Vector3, q: Vector3) -> bool:
	return p.distance_to(q) <= EPS
