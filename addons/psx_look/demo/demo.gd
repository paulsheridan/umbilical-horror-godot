extends Node
## The level through PSXScreen with its materials converted by PSX.convert, the presets to step
## through, and a switch for every part of the look.

const World := preload("res://addons/psx_look/demo/world.gd")
## Loaded by path: the free sampler goes without presets.
const PRESET := "res://addons/psx_look/psx_preset.gd"
const RESOLUTIONS := [240, 480, 1080]
## The draw distance the switch turns on, where the preset has none.
const DRAW_DISTANCE := 12.0

const HELP := [
	"A small ruin seen through the PS1 look: a low resolution, vertices that wobble and textures that warp.",
	"WASD or the arrows walk; drag with the mouse to look.",
	"Each switch on the left turns one part of the look off and on. Resolution steps through 240p, 480p and native.",
	"In your game, one call over your level: PSX.turn_on(screen, level).",
	"? brings this card back.",
]

## Hides the panel, for the store captures.
@export var no_ui := false

var psx := PSXScreen.new()
var world := World.new()
var _fog: Environment
var _res: Button
var _toggles := {}
var _preset := 0
var _look: Resource  # the preset applied last, if any
var _help: Control


func _ready() -> void:
	add_child(psx)
	psx.viewport.add_child(world)
	PSX.convert(world)
	world.dress()
	_fog = world.env.duplicate()
	if no_ui:
		return
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "PSX LOOK"
	box.add_child(title)
	if ResourceLoader.exists(PRESET):
		var presets: Array = load(PRESET).PRESETS.keys()
		var preset := Button.new()
		preset.text = "Preset: PS1"
		preset.pressed.connect(func() -> void:
			_preset = (_preset + 1) % presets.size()
			_apply(load(PRESET).named(presets[_preset]))
			preset.text = "Preset: " + load(PRESET).PRESETS[presets[_preset]].title)
		box.add_child(preset)
	_res = Button.new()
	_res.pressed.connect(func() -> void:
		var i := RESOLUTIONS.find(psx.lines)
		psx.lines = RESOLUTIONS[(i + 1) % RESOLUTIONS.size()]
		_res_text())
	_res_text()
	box.add_child(_res)
	_toggle(box, "Vertex snap", func(on: bool) -> void: PSX.set_param(world, &"snap_pixels", 1.0 if on else 0.0))
	_toggle(box, "Affine textures", func(on: bool) -> void: PSX.set_param(world, &"affine", 1.0 if on else 0.0))
	if psx.material:
		_toggle(box, "Dither", func(on: bool) -> void: psx.dither = on)
		_toggle(box, "15-bit colour", func(on: bool) -> void: psx.color_bits = 5 if on else 8)
		_toggle(box, "Scanlines", func(on: bool) -> void: psx.scanlines = 0.45 if on else 0.0, false)
	_toggle(box, "Fog", _fog_on)
	if ResourceLoader.exists(PSX.TEXTURE):  # PSX Look's, not the free sampler's
		_toggle(box, "Draw distance", _draw_far, false)
	var hint := Label.new()
	hint.text = "WASD / arrows to walk\ndrag to look"
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)
	var again := Button.new()
	again.text = "?"
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void: _help.show())
	box.add_child(again)
	var lines := HELP.duplicate()
	if ResourceLoader.exists(PRESET):
		lines.insert(2, "Preset steps through %d looks, from the PS1's own to CRT, a fog wall and a flashback." % load(PRESET).PRESETS.size())
	_help = _card(ui, lines)


## The card the demo opens with: what it is and how to use it.
func _card(ui: CanvasLayer, lines: Array) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.09, 0.94)
	style.border_color = Color(0.55, 0.4, 0.3)
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 480
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PSX LOOK: how to use this demo"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for line: String in lines:
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 14)
		box.add_child(l)
	var start := Button.new()
	start.text = "Start"
	start.pressed.connect(veil.hide)
	box.add_child(start)
	start.grab_focus.call_deferred()
	veil.visible = Engine.get_write_movie_path() == ""  # not over the store's shots
	return veil


## Applies `preset` over the level's own fog and sets the switches to match.
func _apply(preset) -> void:
	for p in [&"fog_light_color", &"fog_light_energy", &"fog_depth_begin", &"fog_depth_end", &"fog_sky_affect"]:
		world.env.set(p, _fog.get(p))
	world.env.fog_enabled = true
	preset.apply(psx, world, world.env)
	_look = preset
	_res_text()
	for t: Array in [["Vertex snap", preset.snap_pixels > 0.0], ["Affine textures", preset.affine > 0.0],
			["Dither", preset.dither], ["15-bit colour", preset.color_bits < 8],
			["Scanlines", preset.scanlines > 0.0], ["Fog", true], ["Draw distance", preset.draw_distance > 0.0]]:
		if t[0] in _toggles:
			_toggles[t[0]].set_pressed_no_signal(t[1])


func _fog_on(on: bool) -> void:
	world.env.fog_enabled = on
	if _look and _look.fog:
		PSX.set_param(world, &"fog_end", _look.fog_end if on else 0.0)


func _draw_far(on: bool) -> void:
	var far: float = _look.draw_distance if _look and _look.draw_distance > 0.0 else DRAW_DISTANCE
	PSX.set_param(world, &"draw_distance", far if on else 0.0)


func _res_text() -> void:
	_res.text = "Resolution: " + ("Native" if psx.lines >= 1080 else "%dp" % psx.lines)


func _toggle(box: Container, text: String, apply: Callable, on := true) -> void:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(apply)
	box.add_child(b)
	_toggles[text] = b
