@tool
class_name PSXScreen
extends SubViewportContainer
## Draws the 3D under its SubViewport at a PS1 resolution, scaled up in sharp pixels, in 15-bit
## colour with the PS1's dither. Put your 3D scene under it:
##
##     var psx := PSXScreen.new()
##     add_child(psx)
##     psx.viewport.add_child(my_level)
##
## UI outside it stays sharp. With `look` off it draws the 3D as it is, for a game that starts
## without the look and turns it on later (PSX.turn_on).

const COLOR_SHADER := "res://addons/psx_look/shaders/psx_screen.gdshader"

## Off, the 3D is drawn at the screen's resolution in its own colours.
@export var look := true:
	set(value):
		look = value
		material = _color if look else null
		_fit()
## Lines of the low-resolution picture, at least: 240 is the PS1's usual, 480 its high mode. The
## picture is the screen divided by a whole number, so pixels stay square and even.
@export_range(120, 1080) var lines := 240:
	set(value):
		lines = value
		_fit()
@export var dither := true:
	set(value):
		dither = value
		_set_color(&"dither", value)
## Bits per colour channel: 5 is the PS1's, 8 turns the colour reduction off.
@export_range(1, 8) var color_bits := 5:
	set(value):
		color_bits = value
		_set_color(&"color_bits", value)
## 0 is grey, 1 the picture's own colour.
@export_range(0.0, 2.0) var saturation := 1.0:
	set(value):
		saturation = value
		_set_color(&"saturation", value)
## Multiplies the picture, for a night blue or an old photo's brown.
@export var tint := Color.WHITE:
	set(value):
		tint = value
		_set_color(&"tint", value)
## How dark the gaps between the picture's lines are, as on a CRT: 0 is none.
@export_range(0.0, 1.0) var scanlines := 0.0:
	set(value):
		scanlines = value
		_set_color(&"scanlines", value)

var viewport: SubViewport
var _color: ShaderMaterial


func _init() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The container forwards mouse motion to its SubViewport through gui_input.
	# MOUSE_FILTER_IGNORE would skip that stage and silently kill mouse look;
	# PASS still lets the crisp HUD above this layer take its own clicks.
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(COLOR_SHADER):
		_color = ShaderMaterial.new()
		_color.shader = load(COLOR_SHADER)
		material = _color if look else null


func _ready() -> void:
	for child in get_children():
		if child is SubViewport:
			viewport = child
	if not viewport:
		viewport = SubViewport.new()
		viewport.own_world_3d = true
		add_child(viewport)
	viewport.mesh_lod_threshold = 0.0  # LODs picked at this low resolution thin the meshes, and vertex snap with them
	_set_color(&"dither", dither)
	_set_color(&"color_bits", color_bits)
	_set_color(&"saturation", saturation)
	_set_color(&"tint", tint)
	_set_color(&"scanlines", scanlines)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	stretch_shrink = maxi(1, floori(size.y / lines)) if look else 1


func _set_color(param: StringName, value: Variant) -> void:
	if _color:
		_color.set_shader_parameter(param, value)
