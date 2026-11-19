extends PanelContainer
## Crisp in-game PSX Look options. Lives outside the PSX SubViewport, so every
## label stays sharp while the world behind it is 240-line and dithered.

signal closed

const RESOLUTIONS := [160, 192, 240, 480, 1080]
const DENSITIES := [0.0, 2.0, 1.0, 0.5]
const TEXTURE_SIZES := [0, 256, 128, 64, 32]
const PALETTES := [0, 256, 16]

var _sync := false
var _preset: OptionButton
var _preset_names: Array = []   # ids the list was built from, so _refresh can skip it
var _master: CheckButton
var _custom_name: LineEdit


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style())
	if get_child_count() == 0:
		_build()
	if not PSXLook.settings_changed.is_connected(_refresh):
		PSXLook.settings_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "PSX LOOK"
	title.add_theme_color_override("font_color", Color(0.82, 0.62, 0.38))
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "CLOSE  [F5]"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)

	var top := HBoxContainer.new()
	root.add_child(top)
	_master = _check("Master look", func(on: bool) -> void: PSXLook.set_master(on))
	top.add_child(_master)
	_preset = OptionButton.new()
	_preset.custom_minimum_size.x = 230
	_preset.item_selected.connect(func(i: int) -> void:
		if _sync:
			return
		PSXLook.apply_preset(StringName(_preset.get_item_metadata(i)))
	)
	top.add_child(_preset)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	# --- Screen -----------------------------------------------------------
	var screen := _group(col, "SCREEN")
	_option(screen, "Resolution", ["160p", "192p", "240p", "480p", "Native"],
			RESOLUTIONS, func(v: Variant) -> void: PSXLook.set_screen_value("lines", int(v)))
	_check_row(screen, "Dither (4x4 ordered)", "dither", "screen")
	screen.add_child(_check("15-bit colour (5 bit)", func(on: bool) -> void:
		PSXLook.set_screen_value("color_bits", 5 if on else 8)
	))
	_slider(screen, "Saturation", 0.0, 2.0, 0.01, "saturation", "screen")
	_color_row(screen, "Tint", "tint", "screen")

	# --- Geometry ---------------------------------------------------------
	var geom := _group(col, "GEOMETRY")
	_check_slider_row(geom, "Vertex snap", "snap_pixels", 0.0, 4.0, 0.25,
			func(on: bool) -> void: PSXLook.set_material_value("snap_pixels", 1.0 if on else 0.0),
			func(v: float) -> void: PSXLook.set_material_value("snap_pixels", v))
	_check_slider_row(geom, "Affine textures", "affine", 0.0, 1.0, 0.01,
			func(on: bool) -> void: PSXLook.set_material_value("affine", 1.0 if on else 0.0),
			func(v: float) -> void: PSXLook.set_material_value("affine", v))
	_check_row(geom, "Three-point filter", "three_point", "material")
	_check_row(geom, "Vertex colours", "vertex_colors", "material")
	_density_row(geom)

	# --- Textures ---------------------------------------------------------
	var tex := _group(col, "TEXTURES")
	_option(tex, "Colour depth", ["4 bit", "5 bit", "8 bit (off)"], [4, 5, 8],
			func(v: Variant) -> void: PSXLook.set_material_value("texture_bits", int(v)))
	_option(tex, "PS1 texture size", ["Off", "256", "128", "64", "32"], TEXTURE_SIZES,
			func(v: Variant) -> void: PSXLook.set_texture_options(int(v), PSXLook.palette))
	_option(tex, "PS1 palette", ["Off", "256", "16"], PALETTES,
			func(v: Variant) -> void: PSXLook.set_texture_options(PSXLook.texture_size, int(v)))

	# --- Depth ------------------------------------------------------------
	var depth := _group(col, "DEPTH")
	_fog_row(depth)
	_slider(depth, "Fog begin (m)", 0.0, 100.0, 0.5, "fog_begin", "material")
	_slider(depth, "Fog end (m)", 0.0, 200.0, 0.5, "fog_end", "material")
	_color_row(depth, "Fog colour", "fog_color", "material")
	_check_slider_row(depth, "Draw distance", "draw_distance", 8.0, 120.0, 1.0,
			func(on: bool) -> void: PSXLook.set_draw_distance(on),
			func(v: float) -> void: PSXLook.set_draw_distance(PSXLook.draw_distance_on, v))

	# --- Animation --------------------------------------------------------
	var anim := _group(col, "ANIMATION & MATERIALS")
	_category(anim, "Sprites / billboards", "sprites")
	_category(anim, "Flipbook animation", "flipbooks")
	_category(anim, "Wave motion", "waves")
	_category(anim, "Glow", "glow")
	_category(anim, "Cutout", "cutout")
	_category(anim, "Transparent", "transparent")
	_category(anim, "Chrome", "chrome")

	# --- Save -------------------------------------------------------------
	var foot := HBoxContainer.new()
	root.add_child(foot)
	var reset := Button.new()
	reset.text = "RESET TO PRESET"
	reset.pressed.connect(func() -> void: PSXLook.reset_to_defaults())
	foot.add_child(reset)
	_custom_name = LineEdit.new()
	_custom_name.placeholder_text = "custom preset name"
	_custom_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_custom_name)
	var save := Button.new()
	save.text = "SAVE CUSTOM"
	save.pressed.connect(func() -> void:
		var name := _custom_name.text.strip_edges()
		PSXLook.save_custom_preset(name if name != "" else "Custom")
		_custom_name.text = ""
	)
	foot.add_child(save)


# --------------------------------------------------------------------------
# Rows
# --------------------------------------------------------------------------

func _group(parent: Container, title: String) -> VBoxContainer:
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color(0.62, 0.48, 0.32))
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	return box


func _check(text: String, apply: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(func(on: bool) -> void:
		if not _sync:
			apply.call(on)
	)
	return b


func _check_row(parent: Container, text: String, field: String, kind: String) -> void:
	if field == "":
		return
	var b := _check(text, func(on: bool) -> void:
		if kind == "screen":
			PSXLook.set_screen_value(field, on)
		else:
			PSXLook.set_material_value(field, on)
	)
	parent.add_child(b)


func _row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	return row


func _slider(parent: Container, text: String, lo: float, hi: float, step: float,
		field: String, kind: String) -> HSlider:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.set_meta("psx_field", field)
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		if _sync:
			return
		if kind == "screen":
			PSXLook.set_screen_value(field, v)
		else:
			PSXLook.set_material_value(field, v)
	)
	row.add_child(s)
	return s


func _color_row(parent: Container, text: String, field: String, kind: String) -> void:
	var row := _row(parent, text)
	var picker := ColorPickerButton.new()
	picker.set_meta("psx_field", field)
	picker.edit_alpha = false
	picker.color_changed.connect(func(c: Color) -> void:
		if _sync:
			return
		if kind == "screen":
			PSXLook.set_screen_value(field, c)
		else:
			PSXLook.set_material_value(field, c)
	)
	row.add_child(picker)


func _option(parent: Container, text: String, labels: Array, values: Array,
		apply: Callable) -> OptionButton:
	var row := _row(parent, text)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in labels.size():
		opt.add_item(String(labels[i]), i)
		opt.set_item_metadata(i, values[i])
	opt.item_selected.connect(func(i: int) -> void:
		if not _sync:
			apply.call(opt.get_item_metadata(i))
	)
	row.add_child(opt)
	return opt


## A check plus a slider that drive the same field: the box snaps the value on
## or off, the slider carries the strength. The value guard lives here, so the
## call sites only say what to set.
func _check_slider_row(parent: Control, label_text: String, field: String, lo: float,
		hi: float, step: float, on_toggle: Callable, on_value: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var b := _check(label_text, on_toggle)
	b.custom_minimum_size.x = 210
	row.add_child(b)
	var s := HSlider.new()
	s.set_meta("psx_field", field)
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		if not _sync:
			on_value.call(v)
	)
	row.add_child(s)
	return row


func _fog_row(parent: Container) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var b := _check("PS1 fog", func(on: bool) -> void:
		PSXLook.set_material_value("fog", on)
	)
	b.custom_minimum_size.x = 210
	row.add_child(b)


func _density_row(parent: Container) -> void:
	_option(parent, "Geometry density", ["Off", "2 m", "1 m", "0.5 m"], DENSITIES,
			func(v: Variant) -> void: PSXLook.set_density(float(v)))


func _category(parent: Container, text: String, key: String) -> void:
	var b := _check(text, func(on: bool) -> void: PSXLook.set_category(key, on))
	parent.add_child(b)


# --------------------------------------------------------------------------
# Two-way sync
# --------------------------------------------------------------------------

func _refresh() -> void:
	if _master == null:
		return
	_sync = true
	_master.set_pressed_no_signal(PSXLook.master)

	# Renaming the list on every settings change would re-load custom preset
	# files (preset_title does a load), and a dragged slider ticks dozens of
	# times a second. Only rebuild when the ids actually changed.
	var names := PSXLook.preset_names()
	var want: Array = []
	var selected := 0
	for i in names.size():
		want.append(String(names[i]))
		if String(names[i]) == String(PSXLook.current_preset):
			selected = i
	if _preset.item_count == 0 or want != _preset_names:
		_preset_names = want
		_preset.clear()
		for i in names.size():
			var n: StringName = names[i]
			_preset.add_item(PSXLook.preset_title(n), i)
			_preset.set_item_metadata(i, String(n))
	_preset.select(selected)

	_set_all_checks(self)
	_sync = false


func _set_all_checks(node: Node) -> void:
	for child in node.get_children():
		if child is CheckButton:
			_sync_check(child)
		elif child is HSlider:
			_sync_slider(child)
		elif child is ColorPickerButton:
			_sync_color(child)
		elif child is OptionButton and child != _preset:
			_sync_option(child)
		_set_all_checks(child)


func _sync_check(b: CheckButton) -> void:
	var text := b.text
	var on := true
	match text:
		"Master look": on = PSXLook.master
		"Dither (4x4 ordered)": on = PSXLook.dither
		"15-bit colour (5 bit)": on = PSXLook.color_bits < 8
		"Vertex snap": on = PSXLook.snap_pixels > 0.0
		"Affine textures": on = PSXLook.affine > 0.0
		"Three-point filter": on = PSXLook.three_point
		"Vertex colours": on = PSXLook.vertex_colors
		"PS1 fog": on = PSXLook.fog
		"Draw distance": on = PSXLook.draw_distance_on
		"Sprites / billboards": on = PSXLook.sprites
		"Flipbook animation": on = PSXLook.flipbooks
		"Wave motion": on = PSXLook.waves
		"Glow": on = PSXLook.glow
		"Cutout": on = PSXLook.cutout
		"Transparent": on = PSXLook.transparent
		"Chrome": on = PSXLook.chrome
	b.set_pressed_no_signal(on)


func _sync_slider(s: HSlider) -> void:
	var field := String(s.get_meta("psx_field", ""))
	if field == "":
		return
	s.set_value_no_signal(float(PSXLook.get(field)))


func _sync_color(c: ColorPickerButton) -> void:
	var field := String(c.get_meta("psx_field", ""))
	if field != "":
		c.color = PSXLook.get(field)


func _sync_option(o: OptionButton) -> void:
	var row := o.get_parent()
	var label: Label = row.get_child(0) as Label if row != null and row.get_child_count() > 0 else null
	var text := label.text if label != null else ""
	var want: Variant = null
	match text:
		"Resolution": want = PSXLook.lines
		"Colour depth": want = PSXLook.texture_bits
		"PS1 texture size": want = PSXLook.texture_size
		"PS1 palette": want = PSXLook.palette
		"Geometry density": want = PSXLook.density
	if want == null:
		return
	for i in o.item_count:
		if is_equal_approx(float(o.get_item_metadata(i)), float(want)):
			o.select(i)
			return


func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.04, 0.045, 0.97)
	s.border_color = Color(0.42, 0.31, 0.2)
	s.set_border_width_all(1)
	s.set_content_margin_all(18)
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s
