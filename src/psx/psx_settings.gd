class_name PSXSettings
extends RefCounted
## ConfigFile round-trip for PSXLook. Values are plain GDScript variants, so
## colours, booleans, floats and strings all survive unchanged.

const PATH := "user://psx_look.cfg"
const SECTION := "psx_look"


static func save(data: Dictionary, path := PATH) -> Error:
	var cfg := ConfigFile.new()
	for key: String in data:
		cfg.set_value(SECTION, key, data[key])
	return cfg.save(path)


static func load_data(path := PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var out := {}
	for key in cfg.get_section_keys(SECTION):
		out[key] = cfg.get_value(SECTION, key)
	return out


static func remove(path := PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
