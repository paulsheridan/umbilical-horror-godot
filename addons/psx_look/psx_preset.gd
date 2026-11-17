@tool
class_name PSXPreset
extends Resource
## A whole look at once: PSXScreen's resolution and colour, the PSX materials' snap, warp, texture
## filter, texture colours and draw distance, and the fog.
##
##     PSXPreset.named(&"horror").apply(psx, level, world_env.environment)
##
## Save your own as a .tres and apply it the same way. Materials made after `apply` keep their
## own settings.

## The presets that come with the pack, by name.
const PRESETS := {
	&"ps1": {title = "PS1"},
	&"ps1_480": {title = "PS1 480i", lines = 480},
	&"subtle": {title = "Subtle", lines = 480, color_bits = 6, snap_pixels = 0.5, affine = 0.35},
	&"crunchy": {title = "Crunchy", lines = 160, color_bits = 4, snap_pixels = 2.0, texture_bits = 4},
	&"64_bit": {title = "64-Bit", snap_pixels = 0.0, affine = 0.0, three_point = true,
		fog = true, fog_color = Color(0.55, 0.6, 0.7), fog_begin = 4.0, fog_end = 22.0},
	&"handheld": {title = "Handheld", lines = 192, color_bits = 6, dither = false, affine = 0.0},
	&"crt": {title = "CRT", scanlines = 0.45, saturation = 1.15},
	&"horror": {title = "Horror", saturation = 0.55, tint = Color(0.92, 1.0, 0.9),
		fog = true, fog_color = Color(0.06, 0.07, 0.06), fog_begin = 2.0, fog_end = 16.0},
	&"fog_town": {title = "Fog Town", saturation = 0.45, tint = Color(1.0, 0.97, 0.92),
		fog = true, fog_color = Color(0.62, 0.62, 0.6), fog_begin = 1.0, fog_end = 14.0},
	&"night": {title = "Night", saturation = 0.6, tint = Color(0.65, 0.75, 1.0),
		fog = true, fog_color = Color(0.02, 0.03, 0.08), fog_begin = 4.0, fog_end = 24.0},
	&"flashback": {title = "Flashback", saturation = 0.0, tint = Color(1.0, 0.88, 0.7)},
	&"fog_wall": {title = "Fog Wall", saturation = 0.7, draw_distance = 10.0,
		fog = true, fog_color = Color(0.6, 0.6, 0.58), fog_begin = 0.5, fog_end = 9.0},
	&"dark_fog": {title = "Dark Fog", draw_distance = 8.0,
		fog = true, fog_color = Color(0.0, 0.0, 0.0), fog_begin = 0.0, fog_end = 9.0},
}

@export var title := ""
@export_group("Screen")
@export_range(120, 1080) var lines := 240
@export_range(1, 8) var color_bits := 5
@export var dither := true
@export_range(0.0, 2.0) var saturation := 1.0
@export var tint := Color.WHITE
@export_range(0.0, 1.0) var scanlines := 0.0
@export_group("Materials")
@export_range(0.0, 8.0) var snap_pixels := 1.0
@export_range(0.0, 1.0) var affine := 1.0
## A three-point texture filter, in place of nearest pixels.
@export var three_point := false
## Bits a channel the textures' colours keep: 5 is the PS1's 15-bit texels, 8 the textures as they are.
@export_range(1, 8) var texture_bits := 8
## Polygons further than this, in metres, aren't drawn, and pop in as you near them. 0 draws all.
@export_range(0.0, 1000.0) var draw_distance := 0.0
@export_group("Fog")
## The PS1's depth cue on the PSX materials, per vertex, and the sky behind them in its colour.
## Off turns the materials' fog off and leaves the Environment's as it is.
@export var fog := false
@export var fog_color := Color.BLACK
@export var fog_begin := 5.0
@export var fog_end := 30.0


static func named(name: StringName) -> PSXPreset:
	var p := PSXPreset.new()
	for key: String in PRESETS[name]:
		p.set(key, PRESETS[name][key])
	return p


## Any of `screen`, `level` and `environment` can be null, to leave it be.
func apply(screen: PSXScreen, level: Node = null, environment: Environment = null) -> void:
	if screen:
		screen.lines = lines
		screen.color_bits = color_bits
		screen.dither = dither
		screen.saturation = saturation
		screen.tint = tint
		screen.scanlines = scanlines
	if level:
		PSX.set_param(level, &"snap_pixels", snap_pixels)
		PSX.set_param(level, &"affine", affine)
		PSX.set_param(level, &"three_point", three_point)
		PSX.set_param(level, &"texture_bits", texture_bits)
		PSX.set_param(level, &"draw_distance", draw_distance)
		PSX.set_param(level, &"fog_color", fog_color)
		PSX.set_param(level, &"fog_begin", fog_begin)
		PSX.set_param(level, &"fog_end", fog_end if fog else 0.0)
	if environment and fog:
		# Depth fog from where the materials' is whole: the sky (and anything not a PSX material)
		# beyond it in the fog's colour, nothing nearer fogged twice.
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_light_color = fog_color
		environment.fog_light_energy = 1.0
		environment.fog_sun_scatter = 0.0
		environment.fog_aerial_perspective = 0.0
		environment.fog_depth_begin = fog_end
		environment.fog_depth_end = fog_end + 0.01
		environment.fog_sky_affect = 1.0
