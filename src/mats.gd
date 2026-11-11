class_name Mats
extends Object
## Centralized material library for UMBILICAL. Same idea as hallway-demo:
## every surface pulls its StandardMaterial3D from here, so the day real
## textures arrive, the graybox re-skins itself by editing these funcs.

static var _cache: Dictionary = {}


static func _noise(colors: Color) -> StandardMaterial3D:
	var key := "noise_%s" % colors
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colors
	mat.roughness = 0.9
	mat.metallic = 0.0
	# Fine subtle grime so the graybox does not read flat.
	var n := FastNoiseLite.new()
	n.frequency = 0.28
	n.fractal_octaves = 2
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.85, 0.85))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	_cache[key] = mat
	return mat


## Dark scuffed deck plating, slightly oiled.
static func deck() -> StandardMaterial3D:
	var key := "deck"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.28, 0.29, 0.31))
	mat.roughness = 0.55
	mat.metallic = 0.25
	_cache[key] = mat
	return mat


## Painted interior bulkhead, industrial gray-green.
static func wall() -> StandardMaterial3D:
	var key := "wall"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.36, 0.40, 0.38))
	mat.roughness = 0.8
	_cache[key] = mat
	return mat


static func ceil() -> StandardMaterial3D:
	return _noise(Color(0.24, 0.25, 0.26))


## Structural steel w/ chipped industrial paint.
static func hull() -> StandardMaterial3D:
	return _noise(Color(0.42, 0.44, 0.46))


## Machinery: heavier, a bit metallic.
static func machine() -> StandardMaterial3D:
	var key := "machine"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.31, 0.36, 0.38))
	mat.roughness = 0.6
	mat.metallic = 0.35
	_cache[key] = mat
	return mat


## Rubber cable jacket sheath.
static func cable() -> StandardMaterial3D:
	return _noise(Color(0.10, 0.10, 0.11))


## Crated salvage: dark worn wood / fiberboard.
static func crate() -> StandardMaterial3D:
	return _noise(Color(0.38, 0.28, 0.16))


## The dead crew's paper map, hand-inked.
static func paper() -> StandardMaterial3D:
	var key := "paper"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.66, 0.65, 0.58))
	mat.roughness = 0.95
	_cache[key] = mat
	return mat


## Dormant monitor glass: near-black with a cold dim idle glow.
static func screen_off() -> StandardMaterial3D:
	var key := "screen_off"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.05, 0.06, 0.07))
	mat.emission_enabled = true
	mat.emission = Color(0.09, 0.14, 0.19)
	mat.emission_energy_multiplier = 1.0
	_cache[key] = mat
	return mat


## Pale chitin / bone for the stalker's ribs, skull and claws.
static func bone() -> StandardMaterial3D:
	var key := "bone"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.58, 0.55, 0.47))
	mat.roughness = 0.72
	mat.metallic = 0.0
	_cache[key] = mat
	return mat


## Wet, dark body mass for the Processor's maw and limbs. Slightly red so the
## mouth reads against the ship's gray-green walls.
static func flesh() -> StandardMaterial3D:
	var key := "flesh"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.22, 0.08, 0.07))
	mat.roughness = 0.82
	mat.metallic = 0.05
	_cache[key] = mat
	return mat


## Almost invisible mass for silhouettes — reads only when a lamp touches it.
static func shadow() -> StandardMaterial3D:
	var key := "shadow"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.05, 0.05, 0.06))
	mat.roughness = 0.95
	_cache[key] = mat
	return mat


## Amber machine status strip (fabricator "powered" tell).
static func amber() -> StandardMaterial3D:
	var key := "amber"
	if _cache.has(key):
		return _cache[key]
	var mat := _noise(Color(0.4, 0.28, 0.08))
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.38, 0.08)
	mat.emission_energy_multiplier = 1.2
	_cache[key] = mat
	return mat
