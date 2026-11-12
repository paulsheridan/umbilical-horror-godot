class_name Mats
extends Object
## Centralized material palette for UMBILICAL. Every surface pulls its
## StandardMaterial3D from `assets/materials/*.tres`, so the graybox re-skins
## itself by editing a shared project asset rather than regenerating geometry.
##
## The .tres files are produced once by `tools/export_materials.tscn` from the
## original procedural definitions. Re-run that tool only after changing a
## palette definition in code; normal art edits should touch the .tres files.

const MATERIAL_DIR := "res://assets/materials"

static var _cache: Dictionary = {}


static func _mat(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var path := "%s/%s.tres" % [MATERIAL_DIR, key]
	var mat := load(path) as StandardMaterial3D
	if mat == null:
		push_error("Mats: missing palette resource %s" % path)
		mat = StandardMaterial3D.new()
	_cache[key] = mat
	return mat


## Dark scuffed deck plating, slightly oiled.
static func deck() -> StandardMaterial3D:
	return _mat("deck")


## Painted interior bulkhead, industrial gray-green.
static func wall() -> StandardMaterial3D:
	return _mat("wall")


static func ceil() -> StandardMaterial3D:
	return _mat("ceil")


## Structural steel w/ chipped industrial paint.
static func hull() -> StandardMaterial3D:
	return _mat("hull")


## Machinery: heavier, a bit metallic.
static func machine() -> StandardMaterial3D:
	return _mat("machine")


## Rubber cable jacket sheath.
static func cable() -> StandardMaterial3D:
	return _mat("cable")


## Crated salvage: dark worn wood / fiberboard.
static func crate() -> StandardMaterial3D:
	return _mat("crate")


## The dead crew's paper map, hand-inked.
static func paper() -> StandardMaterial3D:
	return _mat("paper")


## Dormant monitor glass: near-black with a cold dim idle glow.
static func screen_off() -> StandardMaterial3D:
	return _mat("screen_off")


## Pale chitin / bone for the stalker's ribs, skull and claws.
static func bone() -> StandardMaterial3D:
	return _mat("bone")


## Wet, dark body mass for the Processor's maw and limbs.
static func flesh() -> StandardMaterial3D:
	return _mat("flesh")


## Almost invisible mass for silhouettes — reads only when a lamp touches it.
static func shadow() -> StandardMaterial3D:
	return _mat("shadow")


## Amber machine status strip (fabricator "powered" tell).
static func amber() -> StandardMaterial3D:
	return _mat("amber")
