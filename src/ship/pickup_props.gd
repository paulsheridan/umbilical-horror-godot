extends RefCounted
## World models and the floating "you can take this" marker for the two
## one-off equipment pickups. The models are deliberately low-poly (a few CSG
## primitives) so they read through the PSX screen and the grainy drone feed.
##
## The base model stays where the pickup has always been. The indicator is a
## bright, unshaded copy that spins and bobs above it: the pale silhouette and
## additive halo survive 15-bit colour, heavy grain and the monochrome feed,
## which the dark machine-coloured boxes did not.

const Mats := preload("res://src/mats.gd")

const FLASHLIGHT_GLOW := Color(1.0, 0.78, 0.34)
const CAMERA_GLOW := Color(0.48, 0.90, 1.0)
const DIM_GLOW := Color(1.0, 0.48, 0.16)

# The markers bloomed into a featureless white blob through the grainy feed, so
# the authored glow is dimmed by a third. The pulse in beyond.gd derives from
# MARKER_LAMP_ENERGY so motion and brightness stay in one place.
const MARKER_BRIGHTNESS := 2.0 / 3.0
const HALO_ALPHA := 0.34 * MARKER_BRIGHTNESS
const MARKER_LAMP_ENERGY := 0.85 * MARKER_BRIGHTNESS

static var _halo_texture: GradientTexture2D


## The actual add-on resting at the pickup site. `bright` swaps the palette for
## the floating copy: an unshaded, self-lit miniature instead of the dark
## machine materials that vanish in the dark.
static func model(kind: String, bright := false) -> Node3D:
	return flashlight_model(bright) if kind == "flashlight" else camera_model(bright)


static func flashlight_model(bright := false) -> Node3D:
	var root := Node3D.new()
	root.name = "PickupModel"
	var main := _glow(Color(1.0, 0.94, 0.76)) if bright else Mats.machine()
	var trim := _glow(DIM_GLOW) if bright else Mats.cable()
	var lens := _glow(FLASHLIGHT_GLOW) if bright else Mats.amber()

	# Barrel lies along -Z; the lens is its bright front face.
	root.add_child(_cyl(0.045, 0.24, Vector3(0.0, 0.0, 0.0), main,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_cyl(0.062, 0.07, Vector3(0.0, 0.0, -0.145), main,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_cyl(0.066, 0.018, Vector3(0.0, 0.0, -0.178), trim,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_cyl(0.048, 0.012, Vector3(0.0, 0.0, -0.188), lens,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_cyl(0.05, 0.026, Vector3(0.0, 0.0, 0.058), trim,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_cyl(0.047, 0.028, Vector3(0.0, 0.0, 0.128), trim,
			Vector3(PI * 0.5, 0.0, 0.0), 8))
	root.add_child(_box(Vector3(0.022, 0.018, 0.05),
			Vector3(0.05, 0.012, 0.015), lens))
	return root


static func camera_model(bright := false) -> Node3D:
	var root := Node3D.new()
	root.name = "PickupModel"
	var main := _glow(Color(0.90, 0.97, 1.0)) if bright else Mats.machine()
	var trim := _glow(Color(0.42, 0.80, 0.96)) if bright else Mats.cable()
	var lens := _glow(CAMERA_GLOW) if bright else Mats.amber()
	var glass := _glow(Color(0.24, 0.55, 0.70)) if bright else Mats.screen_off()

	# Camcorder body, lens on -Z, top handle and side viewfinder.
	root.add_child(_box(Vector3(0.21, 0.13, 0.15), Vector3(0.0, 0.0, 0.01), main))
	root.add_child(_box(Vector3(0.06, 0.15, 0.11), Vector3(0.115, -0.005, 0.02), trim))
	root.add_child(_cyl(0.064, 0.075, Vector3(0.0, 0.0, -0.10), main,
			Vector3(PI * 0.5, 0.0, 0.0), 10))
	root.add_child(_cyl(0.082, 0.028, Vector3(0.0, 0.0, -0.145), trim,
			Vector3(PI * 0.5, 0.0, 0.0), 10))
	root.add_child(_cyl(0.055, 0.012, Vector3(0.0, 0.0, -0.162), lens,
			Vector3(PI * 0.5, 0.0, 0.0), 10))
	root.add_child(_box(Vector3(0.05, 0.032, 0.10), Vector3(0.0, 0.087, 0.01), trim))
	root.add_child(_box(Vector3(0.014, 0.045, 0.014), Vector3(-0.035, 0.065, 0.01), main))
	root.add_child(_box(Vector3(0.014, 0.045, 0.014), Vector3(0.035, 0.065, 0.01), main))
	root.add_child(_box(Vector3(0.075, 0.045, 0.07), Vector3(-0.075, 0.078, 0.03), glass))
	root.add_child(_box(Vector3(0.018, 0.018, 0.012), Vector3(0.06, 0.048, -0.068), lens))
	return root


## A bright, camera-facing halo behind the model. It stays visible when the
## drone feed crushes the shaded sides of the little model to black.
static func halo() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = _get_halo_texture()
	mat.albedo_color = Color(1.0, 1.0, 1.0, HALO_ALPHA)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.56, 0.56)
	var mi := MeshInstance3D.new()
	mi.name = "Halo"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The complete floating marker: model, halo, a slow spin and a soft local
## light. Parent it to the pickup root so the existing show/hide calls hide the
## marker with the item.
static func indicator(kind: String, glow: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "PickupIndicator"
	var icon := Node3D.new()
	icon.name = "Spin"
	root.add_child(icon)
	var body := model(kind, true)
	body.scale = Vector3.ONE * 1.22
	icon.add_child(body)
	var glow_quad := halo()
	glow_quad.material_override.set("albedo_color",
			Color(glow.r, glow.g, glow.b, HALO_ALPHA))
	icon.add_child(glow_quad)

	# A flat ring under the model makes the hover read as a deliberate pickup
	# marker rather than a piece of floating debris.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.albedo_color = Color(glow.r, glow.g, glow.b, 0.85 * MARKER_BRIGHTNESS)
	var ring := CSGTorus3D.new()
	ring.name = "HoverRing"
	ring.inner_radius = 0.145
	ring.outer_radius = 0.17
	ring.sides = 10
	ring.ring_sides = 4
	ring.position = Vector3(0.0, -0.23, 0.0)
	ring.material = ring_mat
	ring.use_collision = false
	root.add_child(ring)

	var lamp := OmniLight3D.new()
	lamp.name = "Glow"
	lamp.light_color = glow
	lamp.light_energy = MARKER_LAMP_ENERGY
	lamp.omni_range = 1.9
	lamp.omni_attenuation = 1.8
	lamp.light_volumetric_fog_energy = 1.2 * MARKER_BRIGHTNESS
	lamp.shadow_enabled = false
	root.add_child(lamp)
	return root


static func _glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


static func _box(size: Vector3, pos: Vector3, mat: Material) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = size
	box.position = pos
	box.material = mat
	box.use_collision = false
	return box


static func _cyl(radius: float, height: float, pos: Vector3, mat: Material,
		rot := Vector3.ZERO, sides := 8) -> CSGCylinder3D:
	var cyl := CSGCylinder3D.new()
	cyl.radius = radius
	cyl.height = height
	cyl.sides = sides
	cyl.position = pos
	cyl.rotation = rot
	cyl.material = mat
	cyl.use_collision = false
	return cyl


static func _get_halo_texture() -> GradientTexture2D:
	if _halo_texture != null:
		return _halo_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_halo_texture = tex
	return tex
