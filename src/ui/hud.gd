extends CanvasLayer
## All 2D presentation for M0: vignette, soft crosshair, meters line, interact
## prompt, message queue, title + pause overlays, F3 debug. Built fully in
## code (hallway-demo pattern); tweak look & copy freely here.

signal start_clicked
signal resume_clicked

# Feed-snow shader: mixes a live screen grab with CRT static. Amount 0 passes
# the picture through; 1 is total signal loss.
const STATIC_SHADER_SRC := "
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec2 g = UV * vec2(320.0, 180.0) + vec2(TIME * 61.0, TIME * 23.0);
	float n = rnd(g);
	float scan = 0.035 * sin(UV.y * 720.0);
	float band = 0.05 * step(0.986, sin(UV.y * 3.0 + TIME * 2.0));
	vec3 snow = vec3(n * 0.9 + scan + band);
	COLOR = vec4(mix(src, snow, clamp(amount, 0.0, 1.0)), 1.0);
}
"

# The still camera: one crude frame per exposure. The grain is FROZEN (no
# TIME term) because this is a photograph, not a live feed; grain that moves
# would read as video. Blacks crushed, highlights blown — read it or don't.
const FEED_SHADER_SRC := "
shader_type canvas_item;
uniform sampler2D feed;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = texture(feed, UV).rgb;
	float g = dot(c, vec3(0.34, 0.45, 0.21));
	// Hard toe and shoulder: the emulsion only records the middle of the
	// range, and it blasts anything bright to paper white. A touch more
	// exposure than a live feed, because a print has to be readable.
	g = clamp((g - 0.008) / 0.42, 0.0, 1.0);
	g = pow(g, 1.10);
	float n = rnd(UV * vec2(340.0, 240.0));
	g += (n - 0.5) * 0.20;
	g *= 0.94 + 0.12 * n;
	float vig = 1.0 - smoothstep(0.30, 0.86, distance(UV, vec2(0.5)));
	g *= mix(0.22, 1.0, vig);
	COLOR = vec4(vec3(clamp(g, 0.0, 1.0)), 1.0);
}
"

# The live tube: the same emulsion as the print, but running. Grain is
# animated, the image is quantised to the 480x270 feed, and stress (drive
# speed + steering) drives tearing, ghosting, rolling wobble and dropped
# scanlines. At rest it settles, but never gets clean.
const LIVE_SHADER_SRC := "
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture;
uniform float stress : hint_range(0.0, 1.0) = 0.0;
uniform float turn : hint_range(-1.0, 1.0) = 0.0;
uniform float dread : hint_range(0.0, 1.0) = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float t = TIME;
	float s = clamp(stress, 0.0, 1.0);
	float tr = clamp(turn, -1.0, 1.0);
	float d = clamp(dread, 0.0, 1.0);
	vec2 uv = UV;

	// Horizontal tear bands. Rows slip sideways more when the chassis is
	// working or when the thing is close enough to poison the signal.
	float band = floor(uv.y * 26.0);
	float jitter = rnd(vec2(band, floor(t * 9.0))) - 0.5;
	uv.x += jitter * (0.002 + s * 0.020 + d * 0.050);
	float glitch = step(0.982 - s * 0.020 - d * 0.075,
			rnd(vec2(band, floor(t * 4.0))));
	uv.x += glitch * (rnd(vec2(band, floor(t * 11.0))) - 0.5)
			* (0.012 + s * 0.055 + d * 0.200);
	uv.y += (rnd(vec2(band, floor(t * 7.0))) - 0.5) * (0.001 + d * 0.006);

	// Lens roll and lag: the picture leans against the turn and wobbles as
	// the tracks fight the deck. Proximity adds a slow, seasick roll.
	uv.x += tr * (0.004 + s * 0.016);
	uv.x += sin(uv.y * 38.0 + t * 6.0) * (0.0015 + s * 0.006 + d * 0.012);
	uv.y += sin(uv.x * 21.0 + t * 4.0) * (0.0010 + s * 0.004 + d * 0.008);
	uv.y += d * 0.014 * sin(t * 1.7 + uv.x * 9.0);
	uv = clamp(uv, vec2(0.001), vec2(0.999));

	// The feed is a low-res tube: quantise to 480x270 before sampling.
	vec2 px = vec2(480.0, 270.0);
	uv = floor(uv * px) / px;

	// Directional smear against the turn, plus vertical drag under load and
	// a proximity ghost that tears the picture off its own frame.
	vec3 col = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float w = 1.0 - fi * 0.16;
		vec2 off = vec2(-tr * fi * (0.004 + s * 0.018),
				fi * (s * 0.003 + d * 0.007));
		col += texture(screen_tex, clamp(uv + off, vec2(0.0), vec2(1.0))).rgb * w;
		wsum += w;
	}
	col /= wsum;

	// Block corruption: whole scanline chunks fall to noise, far more often
	// as the thing closes.
	float corrupt = step(0.994 - s * 0.022 - d * 0.060,
			rnd(vec2(floor(uv.y * 30.0), floor(t * 8.0))));
	col = mix(col, vec3(rnd(uv * 917.0 + t)), corrupt * (0.20 + s * 0.35 + d * 0.40));

	// Emulsion curve, matching the print, then heavier moving grain.
	float g = dot(col, vec3(0.34, 0.45, 0.21));
	g = clamp((g - 0.008) / 0.42, 0.0, 1.0);
	g = pow(g, 1.10);
	float n = rnd(uv * vec2(340.0, 240.0) + vec2(t * 41.0, t * 19.0));
	g += (n - 0.5) * (0.24 + s * 0.30 + d * 0.55);
	g += 0.025 * sin(UV.y * 720.0 + t * 2.0);
	float drop = step(0.998 - s * 0.012 - d * 0.030,
			rnd(vec2(floor(uv.y * 150.0), floor(t * 6.0))));
	g = mix(g, 0.0, drop * 0.55);

	// A bright roll band sweeps the tube as dread rises, then the whole
	// picture dissolves toward snow when it is on top of you.
	float roll = smoothstep(0.040, 0.0, abs(fract(uv.y - t * 0.23) - 0.5));
	g = mix(g, 1.0, roll * d * d * 0.55);
	float wash = smoothstep(0.72, 1.0, d);
	g = mix(g, 0.45 + (n - 0.5) * 1.6, wash * 0.55);

	float vig = 1.0 - smoothstep(0.30 - d * 0.14, 0.86 - d * 0.20,
			distance(UV, vec2(0.5)));
	g *= mix(0.20, 1.0, vig);
	COLOR = vec4(vec3(clamp(g, 0.0, 1.0)), 1.0);
}
"

var _root: Control
var _vignette: TextureRect
var _blind: TextureRect
var _lens: ColorRect
var _live_layer: CanvasLayer
var _live: ColorRect
var _live_mat: ShaderMaterial
var _live_stress := 0.0
var _live_turn := 0.0
var _live_dread := 0.0
var _feed: ColorRect
var _feed_mat: ShaderMaterial
var _feed_enabled := false
var _live_feed := false
var _flash: ColorRect
var _shutter: Control
var _shutter_frac := 0.0
var _static: ColorRect
var _static_mat: ShaderMaterial
var _pilot_status: Label
var _pilot_hint: Label
var _fleet: Label
var _scanner: Control = null
var _end_card: ColorRect
var _end_title: Label
var _end_line: Label
var _end_hint: Label
var _map_view: Control = null
var _crosshair: Control
var _objective: Label
var _objective_line: Label
var _msg: Label
var _prompt: Label
var _title: ColorRect
var _title_vbox: VBoxContainer
var _pause: ColorRect
var _msg_tween: Tween
var _blink_tween: Tween
var _debug_label: Label
var _debug_window := 0.0
var _debug_events := {"motion": 0, "key": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_vignette()
	_build_blind_veil()
	_build_lens()
	_build_live()
	_build_crosshair()
	_build_labels()
	_build_title()
	_build_pause()
	_build_debug()
	_build_pilot()
	_build_feed()
	_build_static()
	_build_shutter()
	_build_end_card()
	_build_map()


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

func _build_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.14),
		Color(0, 0, 0, 0.78),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.05)
	tex.width = 512
	tex.height = 512
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)


## Blind-era veil. With no optics the drone has only a status lamp: a small
## pool of light and the scanner. The raw 3D camera is heavily closed down so
## it reads as an instrument, not a video feed. Sits above the world, below
## the HUD.
func _build_blind_veil() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.20, 0.46, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.04),
		Color(0, 0, 0, 0.34),
		Color(0, 0, 0, 0.84),
		Color(0, 0, 0, 1.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.74)
	tex.width = 512
	tex.height = 512
	_blind = TextureRect.new()
	_blind.texture = tex
	_blind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind.stretch_mode = TextureRect.STRETCH_SCALE
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.visible = false
	_root.add_child(_blind)


## The still-camera lens curtain. Until the video module is racked, the link
## shows a dead black lens between exposures, with the last frame only while
## the print is held. Once live video is online the curtain stays clear. This
## must sit above the 3D world but below every HUD element, so it is built
## before the labels and the photo itself.
func _build_lens() -> void:
	_lens = ColorRect.new()
	_lens.color = Color(0.006, 0.008, 0.009, 1.0)
	_lens.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens.visible = false
	_root.add_child(_lens)


## The live tube sits on its own CanvasLayer BELOW the HUD (layer 4 vs 5).
## Screen-texture shaders render in a separate pass above same-layer siblings,
## so this is the only reliable way to keep the radar and labels on top. It is
## still above the 3D world, and the still print (HUD layer) covers it.
func _build_live() -> void:
	var shader := Shader.new()
	shader.code = LIVE_SHADER_SRC
	_live_mat = ShaderMaterial.new()
	_live_mat.shader = shader
	_live_mat.set_shader_parameter("stress", 0.0)
	_live_mat.set_shader_parameter("turn", 0.0)
	_live_layer = CanvasLayer.new()
	_live_layer.layer = 4
	add_child(_live_layer)
	_live = ColorRect.new()
	_live.material = _live_mat
	_live.set_anchors_preset(Control.PRESET_FULL_RECT)
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.visible = false
	_live_layer.add_child(_live)


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_root.add_child(_crosshair)


func _label(size: int, color: Color = Color(0.85, 0.87, 0.9)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _build_labels() -> void:
	_objective = _label(14, Color(0.6, 0.68, 0.62))
	_objective.text = "O2 91% . H2O 64% . KCAL 55%"
	_objective.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective.position = Vector2(18, 14)
	_root.add_child(_objective)

	_objective_line = _label(13, Color(0.78, 0.62, 0.3))
	_objective_line.text = ""
	_objective_line.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_line.position = Vector2(18, 34)
	_root.add_child(_objective_line)

	_prompt = _label(19, Color(0.78, 0.8, 0.84))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y = -160
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate.a = 0.0
	_root.add_child(_prompt)

	_msg = _label(20, Color(0.9, 0.91, 0.93))
	_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg.position.y = 110
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.modulate.a = 0.0
	_root.add_child(_msg)


func _build_title() -> void:
	_title = ColorRect.new()
	_title.color = Color(0.008, 0.01, 0.013, 1.0)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_title)

	_title_vbox = VBoxContainer.new()
	_title_vbox.set_anchors_preset(Control.PRESET_CENTER)
	_title_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_vbox.add_theme_constant_override("separation", 14)
	_title.add_child(_title_vbox)

	var t := _label(48, Color(0.72, 0.5, 0.38))
	t.text = "UMBILICAL"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_vbox.add_child(t)

	var sub := _label(15, Color(0.6, 0.62, 0.66))
	sub.text = ""
	sub.visible = false
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_vbox.add_child(sub)

	var blank := Control.new()
	blank.custom_minimum_size = Vector2(0, 10)
	_title_vbox.add_child(blank)

	var controls := _label(13, Color(0.42, 0.47, 0.52))
	controls.text = "WASD move   .   SHIFT hurry   .   E inspect   .   ESC pause"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_vbox.add_child(controls)

	var note := _label(12, Color(0.35, 0.4, 0.42))
	note.text = ""
	note.visible = false
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_vbox.add_child(note)

	var hint := _label(16, Color(0.5, 0.55, 0.4))
	hint.text = "CLICK TO BEGIN"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_vbox.add_child(hint)
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_property(hint, "modulate:a", 0.25, 0.8)
	_blink_tween.tween_property(hint, "modulate:a", 1.0, 0.8)

	_title.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_root.accept_event()
			start_clicked.emit()
	)


func _build_pause() -> void:
	_pause = ColorRect.new()
	_pause.color = Color(0.008, 0.01, 0.013, 0.86)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause.add_child(box)

	var p := _label(32, Color(0.7, 0.72, 0.75))
	p.text = "PAUSED"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(p)

	var p2 := _label(13, Color(0.42, 0.47, 0.52))
	p2.text = "ESC or click to resume"
	p2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(p2)

	_pause.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_root.accept_event()
			resume_clicked.emit()
	)


func _build_debug() -> void:
	_debug_label = _label(13, Color(0.5, 0.9, 0.5))
	_debug_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_label.position = Vector2(18, 56)
	_debug_label.visible = false
	_root.add_child(_debug_label)


## Objective text under the meters ("", hides).
func set_objective(text: String) -> void:
	_objective_line.text = text
	_objective_line.visible = text != ""


## Sortie status readout, bottom-left. Lives above the meters line.
func _build_pilot() -> void:
	_pilot_status = _label(15, Color(0.55, 0.85, 0.6))
	_pilot_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pilot_status.position = Vector2(18, -52)
	_pilot_status.size = Vector2(460, 24)
	_root.add_child(_pilot_status)

	_pilot_hint = _label(12, Color(0.4, 0.62, 0.48))
	_pilot_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pilot_hint.position = Vector2(18, -28)
	_pilot_hint.text = "LMB / F photograph (slow recharge)   W/S drive   A/D turn   SHIFT hurry   R reel   B deploy   Q swap   E stand up"
	_pilot_hint.size = Vector2(1040, 20)
	_root.add_child(_pilot_hint)
	_pilot_status.visible = false
	_pilot_hint.visible = false

	# Fleet readout: one line per chassis, the active one marked. This is the
	# only HUD element that says a second bot exists; it must stay quiet.
	_fleet = _label(12, Color(0.42, 0.68, 0.56))
	_fleet.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fleet.position = Vector2(18, -74)
	_fleet.size = Vector2(1040, 20)
	_root.add_child(_fleet)
	_fleet.visible = false


## The optical viewport (main builds the SubViewport; here we dress it).
## Built BEFORE the snow overlay so signal loss covers the feed, never the
## other way round.
func _build_feed() -> void:
	var shader := Shader.new()
	shader.code = FEED_SHADER_SRC
	_feed_mat = ShaderMaterial.new()
	_feed_mat.shader = shader
	_feed = ColorRect.new()
	_feed.material = _feed_mat
	_feed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.visible = false
	_root.add_child(_feed)

	# The shutter flash sits above the photo.
	_flash = ColorRect.new()
	_flash.color = Color(0.95, 0.96, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


## Points the feed shader at the sortie SubViewport's texture.
func set_feed_source(vp: SubViewport) -> void:
	if _feed_mat != null and vp != null:
		_feed_mat.set_shader_parameter("feed", vp.get_texture())


## A mirror-slap flash, then the still frame holds for its moment. The drone
## keeps flying while the photo is on screen: you just stopped looking.
func show_photo() -> void:
	if _feed == null or not _feed_enabled:
		return
	_feed.visible = true
	if _flash != null:
		_flash.color = Color(0.95, 0.96, 1.0, 0.45)
		var tw := create_tween()
		tw.tween_property(_flash, "color:a", 0.0, 0.22)


func hide_photo() -> void:
	if _feed != null:
		_feed.visible = false


## One hard red-white hit when the stalker lunges. The static overlay and the
## stinger do most of the work; this just slams the frame.
func jumpscare() -> void:
	if _flash != null:
		_flash.color = Color(0.95, 0.10, 0.06, 0.60)
		var tw := create_tween()
		tw.tween_property(_flash, "color:a", 0.0, 0.38)


## Whether fitted optics exist at all (blind-era drones have no feed rect).
func set_feed_enabled(on: bool) -> void:
	_feed_enabled = on
	if _feed != null and not on:
		_feed.visible = false   # don't leave a dead module's frame on screen
	if _live != null and not on:
		_live.visible = false
	if _shutter != null:
		set_shutter_visible(on and _pilot_status.visible)
	# Before the video module: the lens goes black except while a photo holds.
	# With live video, the drone camera is the viewport and the lens stays clear.
	if _lens != null:
		_lens.visible = on and _pilot_status.visible and not _live_feed
	if _blind != null:
		_blind.visible = (not on) and _pilot_status.visible


## The recovered video module swaps the black still-camera lens for the live
## drone camera, filtered through the tube shader. The radar stays as a compact
## inset so it keeps charting over the picture.
func set_live_feed(on: bool) -> void:
	_live_feed = on
	if _feed != null and on:
		_feed.visible = false   # a held print must not pin the live view
	if _live != null:
		_live.visible = on and _pilot_status.visible
	if _lens != null:
		_lens.visible = _pilot_status.visible and _feed_enabled and not on
	if _scanner != null:
		if on:
			_scanner.anchor_left = 0.72
			_scanner.anchor_right = 0.98
			_scanner.anchor_top = 0.05
			_scanner.anchor_bottom = 0.34
		else:
			_scanner.anchor_left = 0.18
			_scanner.anchor_right = 0.98
			_scanner.anchor_top = 0.05
			_scanner.anchor_bottom = 0.90
	if _pilot_hint != null:
		if on:
			_pilot_hint.text = "LIVE FEED   F photograph   W/S drive   A/D turn   SHIFT hurry   R reel   B deploy   Q swap   E stand up"
		else:
			_pilot_hint.text = "LMB / F photograph (slow recharge)   W/S drive   A/D turn   SHIFT hurry   R reel   B deploy   Q swap   E stand up"
	if not on:
		set_live_stress(0.0, 0.0)
		set_live_dread(0.0)


## Drive load on the live tube: 0 is parked, 1 is full hurry. Turn is signed
## steering (-1 left, +1 right) and drags the ghost sideways.
func set_live_stress(stress: float, turn: float) -> void:
	_live_stress = clampf(stress, 0.0, 1.0)
	_live_turn = clampf(turn, -1.0, 1.0)
	if _live_mat != null:
		_live_mat.set_shader_parameter("stress", _live_stress)
		_live_mat.set_shader_parameter("turn", _live_turn)


## Proximity poison: 0 is clean, 1 is close enough to dissolve the picture.
## The shadow stalker drives this so it stays unseen and unknowable.
func set_live_dread(dread: float) -> void:
	_live_dread = clampf(dread, 0.0, 1.0)
	if _live_mat != null:
		_live_mat.set_shader_parameter("dread", _live_dread)


## Full-rect feed-snow overlay, driven per frame by Main.
func _build_static() -> void:
	var shader := Shader.new()
	shader.code = STATIC_SHADER_SRC
	_static_mat = ShaderMaterial.new()
	_static_mat.shader = shader
	_static_mat.set_shader_parameter("amount", 0.0)
	_static = ColorRect.new()
	_static.material = _static_mat
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_static)


## Shutter recharge bar, left edge. Fills from empty after a shot; a green
## pip means the camera will take another frame.
func _build_shutter() -> void:
	_shutter = Control.new()
	_shutter.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_shutter.position = Vector2(18, -110)
	_shutter.size = Vector2(14, 220)
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shutter.draw.connect(_draw_shutter)
	_shutter.visible = false
	_root.add_child(_shutter)


func _draw_shutter() -> void:
	var w := 6.0
	var h := _shutter.size.y
	_shutter.draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.1, 0.09, 0.7))
	var f := clampf(_shutter_frac, 0.0, 1.0)
	var fill_h := h * f
	var col := Color(0.55, 0.85, 0.6, 0.9) if f >= 0.999 else Color(0.85, 0.65, 0.25, 0.85)
	_shutter.draw_rect(Rect2(0, h - fill_h, w, fill_h), col)
	_shutter.draw_rect(Rect2(0, 0, w, h), Color(0.5, 0.55, 0.5, 0.5), false, 1.0)
	if f >= 0.999:
		_shutter.draw_circle(Vector2(w * 0.5, -8.0), 3.0, Color(0.55, 0.85, 0.6, 0.95))
	_shutter.draw_string(ThemeDB.fallback_font, Vector2(10, 10), "MB1",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.7, 0.7))


func set_shutter(frac: float) -> void:
	_shutter_frac = frac
	if _shutter != null and _shutter.visible:
		_shutter.queue_redraw()


func set_shutter_visible(on: bool) -> void:
	if _shutter != null:
		_shutter.visible = on


## Host the drone scanner (built by Main, which owns the drone reference).
## In the first drone iteration the radar is the primary display, so it takes
## most of the screen. It is re-parented just above the black lens: above the
## world, below every text overlay and the still photo.
func add_scanner(s: Control) -> void:
	_scanner = s
	s.anchor_left = 0.18
	s.anchor_right = 0.98
	s.anchor_top = 0.05
	s.anchor_bottom = 0.90
	s.visible = false
	_root.add_child(s)
	if _lens != null:
		_root.move_child(s, _lens.get_index() + 1)


func set_piloting(on: bool) -> void:
	_pilot_status.visible = on
	_pilot_hint.visible = on
	if _fleet != null:
		_fleet.visible = on
	if _crosshair != null:
		_crosshair.visible = not on   # the radar carries its own heading marker
	if _scanner != null:
		_scanner.visible = on
	if _live != null:
		_live.visible = on and _live_feed
	if _feed != null and not on:
		_feed.visible = false
	if _lens != null:
		_lens.visible = on and _feed_enabled and not _live_feed
	if _blind != null:
		_blind.visible = on and not _feed_enabled
	set_shutter_visible(on and _feed_enabled)


## One quiet line for the whole fleet: "BOT 1 > 84% | BOT 2 96% [Q] SWAP".
func set_fleet_line(text: String) -> void:
	if _fleet != null:
		_fleet.text = text
		_fleet.visible = _pilot_status.visible and text != ""


func set_static_amount(a: float) -> void:
	_static_mat.set_shader_parameter("amount", clampf(a, 0.0, 1.0))


func set_drone_status(tether_m: float, max_m: float, bars: int, battery: float) -> void:
	var sig := ""
	for i in 5:
		sig += "|" if i < bars else "."
	var strain := (tether_m > max_m - 0.4)
	var optic := "   LIVE FEED" if _live_feed else "   STILL CAM"
	_pilot_status.text = "TETHER %4.1f / %2.0f m %s   SIGNAL %s   CHARGE %3.0f%%%s" % [
		tether_m, max_m, "STRAIN!" if strain else "     ", sig, battery, optic,
	]


# --------------------------------------------------------------------------
# M4 loss card + M5 annotated map
# --------------------------------------------------------------------------

func _build_end_card() -> void:
	_end_card = ColorRect.new()
	_end_card.color = Color(0.008, 0.01, 0.013, 0.0)
	_end_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_card.visible = false
	_root.add_child(_end_card)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_end_card.add_child(box)
	_end_title = _label(36, Color(0.72, 0.48, 0.38))
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_line = _label(16, Color(0.62, 0.64, 0.68))
	_end_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_line)
	_end_hint = _label(13, Color(0.45, 0.55, 0.42))
	_end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_hint)
	_end_card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_root.accept_event()
			hide_end_card()
	)


func show_end_card(title: String, line: String, hint: String) -> void:
	_end_title.text = title
	_end_line.text = line
	_end_hint.text = hint
	_end_card.visible = true
	var tw := create_tween()
	tw.tween_property(_end_card, "color:a", 0.94, 1.6)


func hide_end_card() -> void:
	_end_card.visible = false


func _build_map() -> void:
	_map_view = (load("res://src/ui/map_view.gd") as GDScript).new()
	_map_view.visible = false
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_view)


func show_map(data: Dictionary) -> void:
	if _map_view != null:
		var vs: Vector2 = _map_view.size
		if vs.x < 2.0 or vs.y < 2.0:
			vs = Vector2(1280, 720)
		_map_view.fit_to(vs.x, vs.y)
		_map_view.data = data
		_map_view.visible = true
		_map_view.queue_redraw()


func hide_map() -> void:
	if _map_view != null:
		_map_view.visible = false


# --------------------------------------------------------------------------
# Input (debug counters only; pause is handled by Main)
# --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_debug_events["motion"] = int(_debug_events["motion"]) + 1
	elif event is InputEventKey and event.pressed and not event.echo:
		_debug_events["key"] = int(_debug_events["key"]) + 1
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F3:
		_debug_label.visible = not _debug_label.visible


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------

func _draw_crosshair() -> void:
	var vs := _safe_size(_crosshair)
	var c := vs * 0.5
	var col := Color(0.88, 0.9, 0.9, 0.65)
	_crosshair.draw_circle(c, 2.2, col)
	_crosshair.draw_arc(c, 13.0, 0.0, TAU, 40, Color(0.88, 0.9, 0.9, 0.16), 1.4)


func _safe_size(ctrl: Control) -> Vector2:
	var vs := ctrl.size
	if vs.x < 2.0 or vs.y < 2.0:
		vs = Vector2(1280, 720)
	return vs


# --------------------------------------------------------------------------
# API used by Main
# --------------------------------------------------------------------------

func set_meters(o2: float, h2o: float, kcal: float, clock_hours: float) -> void:
	_objective.text = "O2 %3.0f%%   H2O %3.0f%%   KCAL %3.0f%%   T+%0.1fh" % [
		o2, h2o, kcal, clock_hours,
	]


func set_prompt(text: String) -> void:
	if _msg_tween != null and _msg_tween.is_valid():
		pass  # messages and prompts are independent; keep both channels alive
	var tw := create_tween()
	if _prompt.modulate.a > 0.0 and text != "":
		tw.tween_property(_prompt, "modulate:a", 0.0, 0.08)
	tw.tween_callback(func() -> void: _prompt.text = text)
	if text != "":
		tw.tween_property(_prompt, "modulate:a", 1.0, 0.12)


func show_message(text: String, dur: float = 3.4) -> void:
	_msg.text = text
	if _msg_tween != null and _msg_tween.is_valid():
		_msg_tween.kill()
	_msg.modulate.a = 0.0
	_msg_tween = create_tween()
	_msg_tween.tween_property(_msg, "modulate:a", 1.0, 0.25)
	_msg_tween.tween_interval(dur)
	_msg_tween.tween_property(_msg, "modulate:a", 0.0, 0.6)


func begin_game() -> void:
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 0.0, 1.1)
	tw.tween_callback(func() -> void:
		_title.visible = false
	)


func set_paused_ui(on: bool) -> void:
	_pause.visible = on


func debug_tick(delta: float, fps: int, pos: Vector3, noise_count: int, extra := "") -> void:
	if not _debug_label.visible:
		return
	# Accumulate for a readable half-second window instead of per-frame.
	_debug_window += delta
	if _debug_window < 0.5:
		return
	_debug_window = 0.0
	_debug_label.text = "mode %s  fps %d  pos %.1f %.1f %.1f  noise %d\nmotion %d  keys %d  (mouse %s)%s" % [
		str(Input.get_mouse_mode()),
		fps, pos.x, pos.y, pos.z, noise_count,
		int(_debug_events["motion"]), int(_debug_events["key"]),
		("captured" if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else "NOT captured"),
		("" if extra == "" else "\n" + extra),
	]
	_debug_events["motion"] = 0
	_debug_events["key"] = 0
