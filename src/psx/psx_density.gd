class_name PSXDensity
extends RefCounted
## Optional CSG densification for the PSX look.
##
## PS1 effects are mostly per vertex: snap, affine warp and per-vertex fog all
## read better when a 50 m floor is not one quad. This bakes a CSG shape to a
## mesh, subdivides long triangles to a target edge length, hides the original
## with a discard material (its collision stays live) and leaves the dense
## MeshInstance in its place. Restoring puts the CSG surface and shadow setting
## back and frees the bake.

const DISCARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() { discard; }
"""

const PER_NODE_TRIANGLES := 3500
const TOTAL_TRIANGLES := 120000

static var _discard: ShaderMaterial


## Densifies every eligible CSG primitive under `root`. Returns records for
## restore(). `budget` is the total triangle allowance for this call.
static func apply(root: Node, target: float, budget := TOTAL_TRIANGLES) -> Array:
	var records: Array = []
	if target <= 0.0:
		return records
	for child in root.find_children("*", "CSGShape3D", true, false):
		if budget <= 0:
			break
		var node := child as CSGShape3D
		if node == null or not (node is CSGPrimitive3D):
			continue
		if node.has_meta("psx_exclude") or node.has_meta("psx_density_hidden"):
			continue
		var source: Material = null
		var prim := node as CSGPrimitive3D
		if prim.material is BaseMaterial3D:
			source = prim.material
		elif node.material_override is BaseMaterial3D:
			source = node.material_override
		if source == null:
			continue
		var extent := _extent(node)
		if extent <= target * 1.5:
			continue
		# A CSG that has not drawn yet has no baked mesh; force its shape
		# update so the load-time bake is complete on the first build rather
		# than trickling in on later sweeps.
		node.call("_update_shape")
		var baked: ArrayMesh = node.bake_static_mesh()
		if baked == null:
			continue
		var dense := _subdivide(baked, target, mini(PER_NODE_TRIANGLES, budget))
		if dense == null or dense.get_surface_count() == 0:
			continue
		var used := _triangles(dense)
		if used <= 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "PSXDense"
		mi.mesh = dense
		mi.material_override = source
		mi.cast_shadow = node.cast_shadow
		node.add_child(mi)

		var record := {
			"node": node,
			"baked": mi,
			"original_override": node.material_override,
			"original_visible": node.visible,
			"original_cast_shadow": node.cast_shadow,
		}
		node.material_override = _discard_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("psx_density_hidden", true)
		records.append(record)
		budget -= used
	return records


## Removes every bake and restores the CSG surface.
static func restore(records: Array) -> void:
	for i in range(records.size() - 1, -1, -1):
		var r: Dictionary = records[i]
		var node = r.get("node")
		if node != null and is_instance_valid(node):
			node.material_override = r.get("original_override")
			node.visible = bool(r.get("original_visible", true))
			node.cast_shadow = int(r.get("original_cast_shadow",
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
			node.remove_meta("psx_density_hidden")
		var baked = r.get("baked")
		if baked != null and is_instance_valid(baked):
			var parent: Node = baked.get_parent()
			if parent != null:
				parent.remove_child(baked)
			baked.queue_free()
	records.clear()


static func _discard_material() -> ShaderMaterial:
	if _discard == null:
		var shader := Shader.new()
		shader.code = DISCARD_SHADER
		_discard = ShaderMaterial.new()
		_discard.shader = shader
	return _discard


static func _extent(node: CSGShape3D) -> float:
	if node is CSGBox3D:
		var box: CSGBox3D = node
		return maxf(box.size.x, maxf(box.size.y, box.size.z))
	if node is CSGCylinder3D:
		var cyl: CSGCylinder3D = node
		return maxf(cyl.radius * 2.0, cyl.height)
	if node is CSGSphere3D:
		return (node as CSGSphere3D).radius * 2.0
	if node is CSGTorus3D:
		var torus: CSGTorus3D = node
		return (torus.outer_radius + torus.inner_radius) * 2.0
	# Any other primitive: use its baked bounds' longest side.
	node.call("_update_shape")
	var baked: ArrayMesh = node.bake_static_mesh()
	if baked == null:
		return 0.0
	var aabb := baked.get_aabb()
	return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))


static func _triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays[Mesh.ARRAY_INDEX] == null:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			n += verts.size() / 3
		else:
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			n += index.size() / 3
	return n


## Splits triangles until every edge is at or below `target`, up to `max_tris`
## output triangles. Position, normal, UV and colour are interpolated; the
## material of each surface is carried over.
static func _subdivide(mesh: Mesh, target: float, max_tris: int) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var src_pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if src_pos.is_empty():
			continue
		var src_nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var src_col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var use_nrm := src_nrm.size() == src_pos.size()
		var use_uv := src_uv.size() == src_pos.size()
		var use_col := src_col.size() == src_pos.size()

		var pos := src_pos.duplicate()
		var nrm := src_nrm.duplicate() if use_nrm else PackedVector3Array()
		var uv := src_uv.duplicate() if use_uv else PackedVector2Array()
		var col := src_col.duplicate() if use_col else PackedColorArray()
		var indices := PackedInt32Array()
		var src_index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			src_index = arrays[Mesh.ARRAY_INDEX]
		if src_index.is_empty():
			for i in src_pos.size():
				src_index.append(i)

		var stack: Array[Vector3i] = []
		for i in range(0, src_index.size() - 2, 3):
			stack.append(Vector3i(src_index[i], src_index[i + 1], src_index[i + 2]))
		while not stack.is_empty():
			var tri: Vector3i = stack.pop_back()
			if indices.size() / 3 >= max_tris:
				indices.append_array([tri.x, tri.y, tri.z])
				continue
			var a := pos[tri.x]
			var b := pos[tri.y]
			var c := pos[tri.z]
			var ab := a.distance_squared_to(b)
			var bc := b.distance_squared_to(c)
			var ca := c.distance_squared_to(a)
			var longest := maxf(ab, maxf(bc, ca))
			if longest > target * target:
				var mid := -1
				if ab >= bc and ab >= ca:
					mid = _midpoint(pos, nrm, uv, col, tri.x, tri.y, use_nrm, use_uv, use_col)
					stack.append(Vector3i(tri.x, mid, tri.z))
					stack.append(Vector3i(mid, tri.y, tri.z))
				elif bc >= ca:
					mid = _midpoint(pos, nrm, uv, col, tri.y, tri.z, use_nrm, use_uv, use_col)
					stack.append(Vector3i(tri.x, tri.y, mid))
					stack.append(Vector3i(tri.x, mid, tri.z))
				else:
					mid = _midpoint(pos, nrm, uv, col, tri.z, tri.x, use_nrm, use_uv, use_col)
					stack.append(Vector3i(tri.x, tri.y, mid))
					stack.append(Vector3i(mid, tri.y, tri.z))
			else:
				indices.append_array([tri.x, tri.y, tri.z])

		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = pos
		if use_nrm:
			out_arrays[Mesh.ARRAY_NORMAL] = nrm
		if use_uv:
			out_arrays[Mesh.ARRAY_TEX_UV] = uv
		if use_col:
			out_arrays[Mesh.ARRAY_COLOR] = col
		out_arrays[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


static func _midpoint(pos: PackedVector3Array, nrm: PackedVector3Array,
		uv: PackedVector2Array, col: PackedColorArray, a: int, b: int,
		use_nrm: bool, use_uv: bool, use_col: bool) -> int:
	pos.append((pos[a] + pos[b]) * 0.5)
	if use_nrm:
		nrm.append(((nrm[a] + nrm[b]) * 0.5).normalized())
	if use_uv:
		uv.append((uv[a] + uv[b]) * 0.5)
	if use_col:
		col.append(col[a].lerp(col[b], 0.5))
	return pos.size() - 1
