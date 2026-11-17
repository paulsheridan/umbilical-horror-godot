class_name PSX
## PS1-style materials: make one, or turn a whole scene's StandardMaterial3Ds into them.
##
##     PSX.convert(level)                         # every mesh under level
##     PSX.convert(level, 64, 16)                 # and its textures 64 pixels, 16 colours each
##     mesh.material_override = PSX.make(&"lit", preload("res://crate.png"))
##     PSX.set_param(level, &"affine", 0.0)       # on every PSX material under level
##     add_child(PSX.sprite(preload("res://imp.png"), Vector2i(4, 1), 8.0))  # an upright flipbook
##     PSX.turn_on(psx, level, world_env.environment)  # the look on, where it started off

## Material kinds, each a shaders/psx_<kind>.gdshader.
const KINDS: Array[StringName] = [&"lit", &"unlit", &"cutout", &"transparent", &"chrome", &"glow"]
## PSXTexture, loaded by path: the free sampler goes without it.
const TEXTURE := "res://addons/psx_look/psx_texture.gd"
## PSXPreset, loaded by path for the same reason.
const PRESET := "res://addons/psx_look/psx_preset.gd"


static func has(kind: StringName) -> bool:
	return ResourceLoader.exists(_path(kind))


## A PSX material of `kind`, or lit where that kind isn't installed.
static func make(kind: StringName = &"lit", texture: Texture2D = null, color := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_path(kind if has(kind) else &"lit"))
	m.set_shader_parameter(&"albedo", color)
	if texture:
		m.set_shader_parameter(&"albedo_texture", texture)
	if m.shader.resource_path == _path(&"chrome"):
		m.set_shader_parameter(&"reflection_texture", load("res://addons/psx_look/chrome.png"))
	return m


## The PSX material closest to a BaseMaterial3D: additive blending becomes glow, alpha scissor
## cutout, alpha transparent, opaque unshaded unlit, metallic chrome. Unshaded sources stay unlit. Albedo colour, texture, UV1 scale and
## offset and the billboard mode carry over (a particle billboard's animation frames too).
static func from_material(source: BaseMaterial3D) -> ShaderMaterial:
	var kind := &"lit"
	if source.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		kind = &"glow"
	elif source.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH]:
		kind = &"cutout"
	elif source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		kind = &"transparent"
	elif source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		kind = &"unlit"
	elif source.metallic > 0.5:
		kind = &"chrome"
	var m := make(kind, source.albedo_texture, source.albedo_color)
	m.set_shader_parameter(&"unlit", source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	m.set_shader_parameter(&"uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	m.set_shader_parameter(&"uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	m.set_shader_parameter(&"vertex_colors", source.vertex_color_use_as_albedo)
	if kind == &"cutout":
		m.set_shader_parameter(&"alpha_cut", source.alpha_scissor_threshold)
	m.set_shader_parameter(&"billboard", {BaseMaterial3D.BILLBOARD_ENABLED: 1, BaseMaterial3D.BILLBOARD_FIXED_Y: 2,
			BaseMaterial3D.BILLBOARD_PARTICLES: 1}.get(source.billboard_mode, 0))
	if source.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES:
		m.set_shader_parameter(&"frames", Vector2(source.particles_anim_h_frames, source.particles_anim_v_frames))
	return m


## A sprite: a quad the size of one of `texture`'s `frames` at `pixel_size` metres a pixel, turned
## to the camera upright about its foot (or all the way, about its middle), the frames played at
## `fps`. A cutout, or any other kind: glow for a flame or a spark.
static func sprite(texture: Texture2D, frames := Vector2i.ONE, fps := 0.0, pixel_size := 1.0 / 32.0,
		kind := &"cutout", upright := true) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = texture.get_size() / Vector2(frames) * pixel_size
	if upright:
		quad.center_offset = Vector3(0.0, quad.size.y * 0.5, 0.0)
	var m := make(kind, texture)
	m.set_shader_parameter(&"billboard", 2 if upright else 1)
	m.set_shader_parameter(&"frames", Vector2(frames))
	m.set_shader_parameter(&"fps", fps)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = m
	return mi


## Swaps every BaseMaterial3D on the meshes under `root` (overrides and surface materials) for
## its PSX material, sharing one per source material. Returns how many it made. With
## `texture_size` or `colors`, each texture is made over by PSXTexture.shrink once, as the PS1
## kept it: at most that many pixels on a side, its colours cut to a palette of that many.
static func convert(root: Node, texture_size := 0, colors := 0) -> int:
	var made := {}
	var shrunk: Variant = {} if (texture_size > 0 or colors > 0) and ResourceLoader.exists(TEXTURE) else null
	for node in _meshes(root):
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			mi.material_override = _swap(mi.material_override, made, shrunk, texture_size, colors)
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var source: Material = mi.get_surface_override_material(s)
				if not source:
					source = mi.mesh.surface_get_material(s)
				if source is BaseMaterial3D:
					mi.set_surface_override_material(s, _swap(source, made, shrunk, texture_size, colors))
	return made.size()


## The look on in one call, for a game that starts with it off (a PSXScreen with `look` off, the
## level's materials its own): the screen's look on, the level's materials converted and `preset`
## over both and the Environment's fog (PSXPreset.apply).
static func turn_on(screen: PSXScreen, level: Node, environment: Environment = null, preset := &"ps1") -> void:
	screen.look = true
	PSX.convert(level)
	if ResourceLoader.exists(PRESET):
		load(PRESET).named(preset).apply(screen, level, environment)


## Sets a shader parameter on every PSX material under `root`, for an options menu say.
static func set_param(root: Node, param: StringName, value: Variant) -> void:
	for node in _meshes(root):
		var mi := node as MeshInstance3D
		var mats: Array[Material] = [mi.material_override]
		for s in mi.get_surface_override_material_count():
			mats.append(mi.get_surface_override_material(s))
		for m in mats:
			if m is ShaderMaterial and m.shader and m.shader.resource_path.begins_with("res://addons/psx_look/"):
				m.set_shader_parameter(param, value)


## `shrunk` holds the textures made over so far, or is null to leave them as they are.
static func _swap(source: BaseMaterial3D, made: Dictionary, shrunk: Variant = null, texture_size := 0,
		colors := 0) -> ShaderMaterial:
	if source not in made:
		made[source] = from_material(source)
		var t := source.albedo_texture
		if shrunk != null and t:
			if t not in shrunk:
				shrunk[t] = load(TEXTURE).shrink(t, texture_size, colors)
			made[source].set_shader_parameter(&"albedo_texture", shrunk[t])
	return made[source]


static func _meshes(root: Node) -> Array[Node]:
	var out: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		out.append(root)
	return out


static func _path(kind: StringName) -> String:
	return "res://addons/psx_look/shaders/psx_%s.gdshader" % kind
