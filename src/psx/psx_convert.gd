class_name PSXConvert
extends RefCounted
## CSG- and mesh-aware material conversion for UMBILICAL.
##
## PSX.convert() only walks MeshInstance3D. Almost all of this game's geometry
## is CSG, so this walks CSGShape3D as well, keeps a lossless record of every
## original material and puts the originals back on restore.
##
## The PSX material is derived from the source BaseMaterial3D through
## PSX.from_material(). UMBILICAL's palette is world-triplanar, so that flag is
## carried across too; otherwise a 50 m CSG floor would stretch one noise tile
## across its whole face.

const PSX_TEXTURE := "res://addons/psx_look/psx_texture.gd"


## Converts every unconverted GeometryInstance3D under `root`. `cache` maps a
## source BaseMaterial3D to one shared ShaderMaterial. Returns the entries that
## restore() needs.
static func convert(root: Node, cache: Dictionary = {}) -> Array:
	var entries: Array = []
	var seen := {}
	var nodes: Array[Node] = []
	# The root itself is a convert target too: callers normally pass a container,
	# but a MeshInstance3D/CSGShape3D root has a material of its own (PSX._meshes
	# includes it for that reason).
	if root is CSGShape3D or root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "CSGShape3D", true, false))
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not is_instance_valid(node) or seen.has(node.get_instance_id()):
			continue
		seen[node.get_instance_id()] = true
		if node.has_meta("psx_exclude") or node.has_meta("psx_density_hidden"):
			continue
		if node is CSGShape3D:
			entries.append_array(_convert_csg(node, cache))
		elif node is MeshInstance3D:
			entries.append_array(_convert_mesh(node, cache))
	return entries


## Puts every recorded original material back. Safe after nodes are freed.
static func restore(entries: Array) -> void:
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var node = e.get("node")
		if node == null or not is_instance_valid(node):
			continue
		match String(e.get("kind", "")):
			"csg", "mesh_override":
				node.material_override = e.get("original")
			"mesh_surface":
				node.set_surface_override_material(int(e.get("surface", 0)),
						e.get("original"))


## True for a material this converter (or PSX.from_material) already built.
## Used so repeated sweeps over the world are idempotent.
static func _is_psx(material: Material) -> bool:
	if material == null:
		return false
	if material.has_meta("psx_converted"):
		return true
	var sh := material as ShaderMaterial
	if sh == null or sh.shader == null:
		return false
	return sh.shader.resource_path.begins_with("res://addons/psx_look/")


static func _convert_csg(node: CSGShape3D, cache: Dictionary) -> Array:
	if _is_psx(node.material_override):
		return []
	var source: BaseMaterial3D = null
	if node is CSGPrimitive3D and node.material is BaseMaterial3D:
		source = node.material
	if source == null and node.material_override is BaseMaterial3D:
		source = node.material_override
	if source == null:
		return []
	var psx := shared(source, cache)
	if psx == null:
		return []
	var original: Material = node.material_override
	node.material_override = psx
	return [{
		"node": node,
		"kind": "csg",
		"source": source,
		"psx": psx,
		"original": original,
	}]


static func _convert_mesh(node: MeshInstance3D, cache: Dictionary) -> Array:
	if _is_psx(node.material_override):
		return []
	if node.material_override is BaseMaterial3D:
		var source: BaseMaterial3D = node.material_override
		var psx := shared(source, cache)
		if psx == null:
			return []
		var original: Material = node.material_override
		node.material_override = psx
		return [{
			"node": node,
			"kind": "mesh_override",
			"source": source,
			"psx": psx,
			"original": original,
		}]
	if node.mesh == null:
		return []
	var entries: Array = []
	for surface in node.mesh.get_surface_count():
		var existing: Material = node.get_surface_override_material(surface)
		if _is_psx(existing):
			continue
		var original: Material = existing
		var source: Material = original
		if not (source is BaseMaterial3D):
			source = node.mesh.surface_get_material(surface)
		if not (source is BaseMaterial3D):
			continue
		var psx := shared(source as BaseMaterial3D, cache)
		if psx == null:
			continue
		node.set_surface_override_material(surface, psx)
		entries.append({
			"node": node,
			"kind": "mesh_surface",
			"surface": surface,
			"source": source,
			"psx": psx,
			"original": original,
		})
	return entries


## One PSX ShaderMaterial per source material, with the source's UV1 setup and
## triplanar behaviour carried over. Shared by every CSG face and mesh surface
## that uses the same source.
static func shared(source: BaseMaterial3D, cache: Dictionary) -> ShaderMaterial:
	if cache.has(source):
		return cache[source]
	var psx := PSX.from_material(source)
	if psx == null:
		return null
	psx.set_meta("psx_converted", true)
	if source.uv1_triplanar:
		psx.set_shader_parameter(&"triplanar", true)
		psx.set_shader_parameter(&"triplanar_world", source.uv1_world_triplanar)
		var scale := source.uv1_scale.x
		psx.set_shader_parameter(&"triplanar_scale", scale if absf(scale) > 0.0001 else 1.0)
		psx.set_shader_parameter(&"triplanar_offset",
				Vector3(source.uv1_offset.x, source.uv1_offset.y, source.uv1_offset.z))
	else:
		psx.set_shader_parameter(&"triplanar", false)
	cache[source] = psx
	return psx


## Replaces each material's texture with the PS1-shrunk version. `state` caches
## by source texture, so the whole world bakes one copy of each. Viewport
## textures and textures that cannot produce an image are left alone.
static func shrink_textures(cache: Dictionary, size: int, colors: int,
		state: Dictionary = {}) -> void:
	if not ResourceLoader.exists(PSX_TEXTURE):
		return
	if size <= 0 and colors <= 0:
		return
	for source: BaseMaterial3D in cache.keys():
		var psx: ShaderMaterial = cache[source]
		var texture: Texture2D = source.albedo_texture
		if texture == null or texture is ViewportTexture:
			continue
		# The cache is checked before decoding: a rebuilt world must not pay for
		# an image it already shrank (textures are expensive to read back).
		var key := texture.get_instance_id()
		if state.has(key):
			psx.set_shader_parameter(&"albedo_texture", state[key])
			continue
		# Not only ImageTexture: the albedos here are NoiseTexture2D,
		# CompressedTexture2D and GradientTexture2D, all of which hand back an
		# image that PSXTexture.shrink can bake (the addon shrinks any texture).
		var image: Image = texture.get_image()
		if image == null:
			continue
		state[key] = load(PSX_TEXTURE).shrink(texture, size, colors)
		psx.set_shader_parameter(&"albedo_texture", state[key])
