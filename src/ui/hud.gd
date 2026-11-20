extends CanvasLayer
## All 2D presentation for M0: vignette, soft crosshair, meters line, interact
## prompt, message queue, title + pause overlays, F3 debug. Still built in
## code; converting this to a HUD scene is the remaining UI work.

signal lore_clicked
signal resume_clicked
signal psx_open_requested
signal psx_closed

const MapView := preload("res://src/ui/map_view.gd")
const PSXPanel := preload("res://src/ui/psx_panel.gd")
## The scanner owns the echo range; the HUD only formats it.
const SCANNER_SCRIPT := preload("res://src/ui/scanner.gd")
## Design-space fallback for controls that have not been laid out yet.
const DESIGN_SIZE := Vector2(1280, 720)
## Five-character signal bar, one glyph row per level.
const SIG_BARS := [".....", "|....", "||...", "|||..", "||||.", "|||||"]
## The intro lore card, one string per paragraph. Authored copy: tests compare
## the built labels against this, so edits here are the single source of truth.
const LORE_PARAGRAPHS: Array[String] = [
	"Something has attached itself to the hull of the ship. The crew began acting strangely, then changing completely. Things became dangerous and you barricaded yourself here, in the ship's workshop for hull repair drones.",
	"Press E on the chair to pilot a drone.",
	"They're not made for this, so both visual feedback and navigation will be poor, and only a still image camera and basic radar are available without new modules.",
	"If you can find new modules to add, bring them back here, then press R to reel your drone back into the workshop and then press E on the fabricator in the corner to upgrade drones for future missions.",
]

# Feed-snow shader: a window-local CRT static veil. Amount 0 is clear; 1 is
# total signal loss. It never covers the radar window.
const STATIC_SHADER_SRC := "
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 g = UV * vec2(320.0, 180.0) + vec2(TIME * 61.0, TIME * 23.0);
	float n = rnd(g);
	float scan = 0.035 * sin(UV.y * 720.0);
	float band = 0.05 * step(0.986, sin(UV.y * 3.0 + TIME * 2.0));
	vec3 snow = vec3(n * 0.9 + scan + band);
	COLOR = vec4(clamp(snow, 0.0, 1.0), clamp(amount, 0.0, 1.0));
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
uniform sampler2D feed;
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
		col += texture(feed, clamp(uv + off, vec2(0.0), vec2(1.0))).rgb * w;
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
	g += (n - 0.5) * (0.30 + s * 0.32 + d * 0.55);
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
var _desk: Control
var _cam_window: PanelContainer
var _cam_body: Control
var _cam_title: Label
var _cam_state: Label
var _radar_window: PanelContainer
var _radar_body: Control
var _radar_state: Label
var _vignette: TextureRect
var _blind: TextureRect
var _lens: ColorRect
var _live: ColorRect
var _live_mat: ShaderMaterial
var _live_stress := 0.0
var _live_turn := 0.0
var _live_dread := 0.0
var _cam_raw: TextureRect
var _feed: ColorRect
var _feed_mat: ShaderMaterial
var _feed_enabled := false
var _live_feed := false
var _photo_showing := false
## Debug vision hides the tube shader entirely, so the drone camera reads as
## clean full-colour video. The flag is HUD-local; main owns the toggle.
var _debug_view := false
var _flash: ColorRect
var _shutter: Control
var _shutter_frac := -1.0
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
## Last host rect handed to MapView.fit_to(), so a per-frame show_map() only
## re-fits when the window actually changed size.
var _map_fit := Vector2(-1.0, -1.0)
var _crosshair: Control
var _objective: Label
var _objective_line: Label
var _msg: Label
var _prompt: Label
## Subtitles are their own channel: quiet, bottom-centre, never the objective
## banner or the interaction prompt.
var _subtitle: Label
var _zone_beat: Label
var _title: ColorRect
var _title_vbox: VBoxContainer
var _lore: ColorRect
var _lore_vbox: VBoxContainer
## The paragraph labels, in order, so tests can assert the copy verbatim.
var _lore_labels: Array[Label] = []
var _lore_blink_tween: Tween
## The title->lore fade-in; begin_game() kills it so a swap mid-fade cannot
## leave the card drawing at partial alpha behind the game.
var _lore_fade_tween: Tween
var _pause: ColorRect
var _psx_veil: ColorRect
var _psx_panel: PanelContainer
var _msg_tween: Tween
var _prompt_tween: Tween = null
var _subtitle_tween: Tween
var _zone_tween: Tween
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
	_build_desk()
	_build_blind_veil()
	_build_lens()
	_build_live()
	_build_crosshair()
	_build_labels()
	_build_title()
	_build_lore()
	_build_pause()
	_build_debug()
	_build_pilot()
	_build_feed()
	_build_static()
	_build_shutter()
	_build_end_card()
	_build_map()
	_build_psx()


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


## The pilot desktop: a flat work surface with two independent windows. The
## optical channel is the big picture — stills and live video alike — and the
## radar is a small instrument panel beside it. The radar is never covered by
## the camera, a print, snow or an exposure flash.
func _build_desk() -> void:
	_desk = Control.new()
	_desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	_desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desk.visible = false
	_desk.draw.connect(_draw_desk)
	_root.add_child(_desk)

	var cam := _build_window("OPTICS")
	_cam_window = cam["panel"]
	_cam_body = cam["body"]
	_cam_title = cam["title"]
	_cam_state = cam["state"]
	_desk.add_child(_cam_window)

	var radar := _build_window("RADAR")
	_radar_window = radar["panel"]
	_radar_body = radar["body"]
	_radar_state = radar["state"]
	_radar_state.text = "%d m" % int(SCANNER_SCRIPT.RANGE)
	_desk.add_child(_radar_window)
	_layout_windows(false)


func _build_window(title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.041, 0.047, 0.98)
	style.border_color = Color(0.28, 0.31, 0.34, 0.95)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 9
	style.shadow_offset = Vector2(3, 4)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var head := PanelContainer.new()
	head.custom_minimum_size = Vector2(0, 24)
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.105, 0.118, 0.132, 1.0)
	hs.border_color = Color(0.24, 0.27, 0.3, 1.0)
	hs.border_width_bottom = 1
	hs.content_margin_left = 8.0
	hs.content_margin_right = 8.0
	hs.content_margin_top = 2.0
	hs.content_margin_bottom = 2.0
	head.add_theme_stylebox_override("panel", hs)
	box.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	head.add_child(row)
	var name_label := _label(11, Color(0.72, 0.76, 0.79))
	name_label.text = title
	row.add_child(name_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var state := _label(10, Color(0.54, 0.78, 0.58))
	state.text = "STILL"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(state)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	return {"panel": panel, "body": body, "title": name_label, "state": state}


func _layout_windows(live: bool) -> void:
	if _cam_window == null or _radar_window == null:
		return
	# The picture owns the desktop in both modes: stills and live video are read
	# at 16:9, while the radar is a small square instrument panel on the right.
	# These spans are the largest that keep that arrangement intact, recovered
	# from the desk margins at a 1280x720 reference. Invariants:
	# 1. Optics is 16:9: width 0.777-0.012 and height 0.805-0.040 both span 0.765,
	#    so equal anchor spans stay square-on at any 16:9 viewport.
	# 2. Radar body stays square: 0.200*1280 = 256 px wide, and the height span
	#    0.389*720 minus the fixed 24 px title bar also leaves 256 px.
	# 3. Width ratio optics:radar stays near the authored ~3.7:1 (0.765:0.200).
	# 4. Both clear the 112 px pilot bar from _draw_desk (top at 0.844): the
	#    optics bottom at 0.805 keeps ~28 px of breathing room above it.
	_set_window_rect(_cam_window, 0.012, 0.040, 0.777, 0.805)
	_set_window_rect(_radar_window, 0.790, 0.040, 0.990, 0.429)
	_cam_state.text = "LIVE" if live else "STILL"


func _set_window_rect(panel: Control, l: float, t: float, r: float, b: float) -> void:
	panel.anchor_left = l
	panel.anchor_top = t
	panel.anchor_right = r
	panel.anchor_bottom = b
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0


func _draw_desk() -> void:
	var vs := _safe_size(_desk)
	_desk.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.012, 0.015, 0.019))
	for x in range(0, int(vs.x), 56):
		_desk.draw_line(Vector2(x, 0), Vector2(x, vs.y),
				Color(0.24, 0.28, 0.3, 0.045), 1.0)
	for y in range(0, int(vs.y), 56):
		_desk.draw_line(Vector2(0, y), Vector2(vs.x, y),
				Color(0.24, 0.28, 0.3, 0.045), 1.0)
	var bar := Rect2(0.0, vs.y - 112.0, vs.x, 112.0)
	_desk.draw_rect(bar, Color(0.022, 0.027, 0.032, 0.98))
	_desk.draw_line(bar.position, Vector2(bar.end.x, bar.position.y),
			Color(0.25, 0.29, 0.32, 0.55), 1.0)


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


## The still-camera lens curtain inside the optics window. Until the video
## module is racked, the window shows a dead black lens between exposures, with
## the last frame only while the print is held.
func _build_lens() -> void:
	_lens = ColorRect.new()
	_lens.color = Color(0.006, 0.008, 0.009, 1.0)
	_lens.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens.visible = false
	_cam_body.add_child(_lens)


## The live tube is local to the optics window: its shader samples the drone
## feed texture directly instead of the screen, so the radar window is never
## filtered, torn or covered by it.
func _build_live() -> void:
	var shader := Shader.new()
	shader.code = LIVE_SHADER_SRC
	_live_mat = ShaderMaterial.new()
	_live_mat.shader = shader
	_live_mat.set_shader_parameter("stress", 0.0)
	_live_mat.set_shader_parameter("turn", 0.0)
	_cam_raw = TextureRect.new()
	_cam_raw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_raw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam_raw.stretch_mode = TextureRect.STRETCH_SCALE
	_cam_raw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_raw.visible = false
	_cam_body.add_child(_cam_raw)
	_live = ColorRect.new()
	_live.material = _live_mat
	_live.set_anchors_preset(Control.PRESET_FULL_RECT)
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.visible = false
	_cam_body.add_child(_live)


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

	_subtitle = _label(16, Color(0.86, 0.82, 0.70))
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.anchor_left = 0.5
	_subtitle.anchor_right = 0.5
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle.position.y = -112
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)

	# Zone stencil: a deck marking, not a mission popup. It fades fast.
	_zone_beat = _label(22, Color(0.58, 0.72, 0.66))
	_zone_beat.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zone_beat.anchor_left = 0.5
	_zone_beat.anchor_right = 0.5
	_zone_beat.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_zone_beat.position.y = 168
	_zone_beat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_beat.modulate.a = 0.0
	_root.add_child(_zone_beat)


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
	controls.text = "WASD   SHIFT   E   ESC"
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

	_title.gui_input.connect(_on_title_gui_input)


## The title is a two-step gate: this click only swaps in the lore card, and
## the lore card's own click starts the game. Named so tests can drive it.
func _on_title_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		_title.visible = false
		_lore.visible = true
		_lore.modulate.a = 0.0
		_lore_fade_tween = create_tween()
		_lore_fade_tween.tween_property(_lore, "modulate:a", 1.0, 0.4)


func _on_lore_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		lore_clicked.emit()


## The second intro screen. Same near-black veil as the title so the swap reads
## as one screen changing its mind, not a new window opening.
func _build_lore() -> void:
	_lore = ColorRect.new()
	_lore.color = Color(0.008, 0.01, 0.013, 1.0)
	_lore.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lore.visible = false
	_root.add_child(_lore)

	_lore_vbox = VBoxContainer.new()
	_lore_vbox.set_anchors_preset(Control.PRESET_CENTER)
	_lore_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lore_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lore_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_lore_vbox.add_theme_constant_override("separation", 16)
	_lore.add_child(_lore_vbox)

	# Warm grey, a step dimmer than the title's control line, so the card reads
	# as an aside rather than a second title screen.
	for text: String in LORE_PARAGRAPHS:
		var p := _label(17, Color(0.55, 0.54, 0.5))
		p.text = text
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size.x = 720
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lore_vbox.add_child(p)
		_lore_labels.append(p)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	_lore_vbox.add_child(gap)

	var hint := _label(14, Color(0.5, 0.55, 0.4))
	hint.text = "CLICK"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lore_vbox.add_child(hint)
	# Its own tween: the title's blink keeps running until the swap, and two
	# loops driving the same property would fight.
	_lore_blink_tween = create_tween().set_loops()
	_lore_blink_tween.tween_property(hint, "modulate:a", 0.25, 0.8)
	_lore_blink_tween.tween_property(hint, "modulate:a", 1.0, 0.8)

	_lore.gui_input.connect(_on_lore_gui_input)


func _build_pause() -> void:
	_pause = ColorRect.new()
	_pause.color = Color(0.008, 0.01, 0.013, 0.86)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)

	# Clicking the dark background resumes; clicking the panel does not.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.05, 0.055, 0.96)
	style.border_color = Color(0.36, 0.28, 0.2)
	style.set_border_width_all(1)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 300
	panel.add_child(box)

	var p := _label(32, Color(0.7, 0.72, 0.75))
	p.text = "PAUSED"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(p)

	var resume := Button.new()
	resume.text = "RESUME"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(func() -> void: resume_clicked.emit())
	box.add_child(resume)

	var psx := Button.new()
	psx.text = "PSX LOOK"
	psx.focus_mode = Control.FOCUS_NONE
	psx.pressed.connect(func() -> void: psx_open_requested.emit())
	box.add_child(psx)

	var p2 := _label(13, Color(0.42, 0.47, 0.52))
	p2.text = "ESC / CLICK"
	p2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(p2)

	_pause.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_root.accept_event()
			resume_clicked.emit()
	)


## Crisp PSX options overlay. It sits above every other HUD layer and outside
## the PSX SubViewport, so the panel itself is never low-resolution.
func _build_psx() -> void:
	_psx_veil = ColorRect.new()
	_psx_veil.color = Color(0.004, 0.005, 0.007, 0.82)
	_psx_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_psx_veil.visible = false
	_psx_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_psx_veil)
	_psx_veil.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_root.accept_event()
			close_psx_panel()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_psx_veil.add_child(center)
	_psx_panel = PSXPanel.new()
	_psx_panel.custom_minimum_size = Vector2(660, 680)
	center.add_child(_psx_panel)
	_psx_panel.closed.connect(close_psx_panel)


func open_psx_panel() -> void:
	_psx_veil.visible = true
	_psx_panel.visible = true


func close_psx_panel() -> void:
	if not _psx_veil.visible:
		return
	_psx_veil.visible = false
	psx_closed.emit()


func psx_panel_open() -> bool:
	return _psx_veil != null and _psx_veil.visible


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
	_pilot_hint.text = "F PHOTO   L LIGHT   WASD DRIVE   SHIFT HURRY   R REEL   B DEPLOY   Q SWAP   E EXIT"
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
	_cam_body.add_child(_feed)

	# The shutter flash sits above the photo, inside the optics window.
	_flash = ColorRect.new()
	_flash.color = Color(0.95, 0.96, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_body.add_child(_flash)


## Points both optical shaders and the raw debug view at the sortie viewport.
func set_feed_source(vp: SubViewport) -> void:
	if vp == null:
		return
	var tex := vp.get_texture()
	if _feed_mat != null:
		_feed_mat.set_shader_parameter("feed", tex)
	if _live_mat != null:
		_live_mat.set_shader_parameter("feed", tex)
	if _cam_raw != null:
		_cam_raw.texture = tex


## A mirror-slap flash, then the still frame holds in the optics window. The
## radar window is untouched and keeps charting while the print is up.
func show_photo() -> void:
	if _feed == null or not _feed_enabled:
		return
	_photo_showing = true
	_sync_optics()
	if _flash != null:
		_flash.color = Color(0.95, 0.96, 1.0, 0.45)
		var tw := create_tween()
		tw.tween_property(_flash, "color:a", 0.0, 0.22)


func hide_photo() -> void:
	_photo_showing = false
	_sync_optics()


## One hard red-white hit when the stalker lunges. Window-local now, so the
## radar remains readable.
func jumpscare() -> void:
	if _flash != null:
		_flash.color = Color(0.95, 0.10, 0.06, 0.60)
		var tw := create_tween()
		tw.tween_property(_flash, "color:a", 0.0, 0.38)


## Whether the still camera is available. The still camera is standard kit, so
## this is normally always true; the switch remains for module-loss teardown.
func set_feed_enabled(on: bool) -> void:
	_feed_enabled = on
	if not on:
		_photo_showing = false
	_sync_optics()


## Debug vision keeps the live channel but drops the tube shader, showing the
## raw colour render inside the optics window only.
func set_debug_view(on: bool) -> void:
	_debug_view = on
	_sync_optics()


## The recovered video module fills the large optics window with the live drone
## feed. The radar keeps its own small instrument window alongside it.
func set_live_feed(on: bool) -> void:
	_live_feed = on
	_layout_windows(on)
	if not on:
		set_live_stress(0.0, 0.0)
		set_live_dread(0.0)
	_sync_optics()


## One place that decides what the optics window is showing. The radar window
## and its scanner are deliberately outside this function.
func _sync_optics() -> void:
	if _cam_raw != null:
		_cam_raw.visible = _pilot_status.visible and _live_feed and _debug_view
	if _live != null:
		_live.visible = _pilot_status.visible and _live_feed and not _debug_view
	if _lens != null:
		_lens.visible = _pilot_status.visible and not _live_feed
	if _feed != null:
		_feed.visible = _pilot_status.visible and _feed_enabled and _photo_showing
	if _shutter != null:
		_shutter.visible = _pilot_status.visible and _feed_enabled
	if _blind != null:
		_blind.visible = false


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
	_cam_body.add_child(_static)


## Shutter recharge bar, left edge. Fills from empty after a shot; a green
## pip means the camera will take another frame.
func _build_shutter() -> void:
	_shutter = Control.new()
	_shutter.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_shutter.position = Vector2(10, -88)
	_shutter.size = Vector2(12, 176)
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shutter.draw.connect(_draw_shutter)
	_shutter.visible = false
	_cam_body.add_child(_shutter)


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


func set_shutter(frac: float) -> void:
	# Pinned at full charge between shots: skip the redraw unless it moved.
	if is_equal_approx(frac, _shutter_frac):
		return
	_shutter_frac = frac
	if _shutter != null and _shutter.visible:
		_shutter.queue_redraw()


func set_shutter_visible(on: bool) -> void:
	if _shutter != null:
		_shutter.visible = on


## Host the drone scanner inside its own window. Main owns the drone
## reference; the HUD owns the frame around it.
func add_scanner(s: Control) -> void:
	_scanner = s
	if _radar_body != null:
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		s.visible = false
		_radar_body.add_child(s)


func set_piloting(on: bool) -> void:
	_pilot_status.visible = on
	_pilot_hint.visible = on
	if _fleet != null:
		_fleet.visible = on
	if _crosshair != null:
		_crosshair.visible = not on   # the radar carries its own heading marker
	if _scanner != null:
		_scanner.visible = on
	if _desk != null:
		_desk.visible = on
	if not on:
		_photo_showing = false
	if on:
		_layout_windows(_live_feed)
	_sync_optics()


## One quiet line for the whole fleet: "BOT 1 > 84% | BOT 2 96% [Q] SWAP".
func set_fleet_line(text: String) -> void:
	if _fleet != null:
		_fleet.text = text
		_fleet.visible = _pilot_status.visible and text != ""


func set_static_amount(a: float) -> void:
	_static_mat.set_shader_parameter("amount", clampf(a, 0.0, 1.0))


func set_drone_status(tether_m: float, max_m: float, bars: int, battery: float) -> void:
	var sig: String = SIG_BARS[clampi(bars, 0, 5)]
	var strain := (tether_m > max_m - 0.4)
	var optic := "   DEBUG" if _debug_view else ("   LIVE" if _live_feed else "   STILL")
	_pilot_status.text = "TETHER %4.1f / %2.0f m %s   SIGNAL %s   CHARGE %3.0f%%%s" % [
		tether_m, max_m, "STRAIN" if strain else "      ", sig, battery, optic,
	]


# --------------------------------------------------------------------------
# Module-loss card + M5 annotated map
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
	# Reset the veil so the next loss fades in from black instead of popping.
	_end_card.color.a = 0.0


func _build_map() -> void:
	_map_view = MapView.new()
	_map_view.visible = false
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_map_view)
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_map(data: Dictionary) -> void:
	if _map_view != null:
		var vs: Vector2 = _map_view.size
		if vs.x < 2.0 or vs.y < 2.0:
			vs = DESIGN_SIZE
		# Main calls this every frame the map is open. fit_to() re-lays out and
		# redraws, so it only runs when the host rect changed; assigning `data`
		# carries no redraw of its own, so one request per call keeps the ink
		# fresh without ever queueing the same frame twice.
		if not vs.is_equal_approx(_map_fit):
			_map_fit = vs
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
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F3:
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
		vs = DESIGN_SIZE
	return vs


# --------------------------------------------------------------------------
# API used by Main
# --------------------------------------------------------------------------

func set_meters(o2: float, h2o: float, kcal: float, clock_hours: float) -> void:
	_objective.text = "O2 %3.0f%%   H2O %3.0f%%   KCAL %3.0f%%   T+%0.1fh" % [
		o2, h2o, kcal, clock_hours,
	]


func set_prompt(text: String) -> void:
	# Prompts and messages are independent channels, so this kill stays local:
	# an overlapping prompt must not leave the old chain's callback running.
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	var tw := create_tween()
	if _prompt.modulate.a > 0.0 and text != "":
		tw.tween_property(_prompt, "modulate:a", 0.0, 0.08)
	tw.tween_callback(func() -> void: _prompt.text = text)
	if text != "":
		tw.tween_property(_prompt, "modulate:a", 1.0, 0.12)
	_prompt_tween = tw


## The shared scaffold of the three text channels: reset, set, rise, hold, fall.
## Callers keep their own Tween member so kill-previous stays per-channel.
func _fade_pulse(label: Label, text: String, peak: float, in_t: float,
		hold: float, out_t: float) -> Tween:
	label.modulate.a = 0.0
	label.text = text
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", peak, in_t)
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, out_t)
	return tw


func show_message(text: String, dur: float = 3.4) -> void:
	if _msg_tween != null and _msg_tween.is_valid():
		_msg_tween.kill()
	_msg_tween = _fade_pulse(_msg, text, 1.0, 0.25, dur, 0.6)


## The subtitle channel. Slower and quieter than show_message(); used for
## voices the player is overhearing rather than instructions.
func show_subtitle(text: String, dur: float = 3.0) -> void:
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = _fade_pulse(_subtitle, text, 0.92, 0.18, dur, 0.55)


## Deck stencil / entry beat. Two short lines, then gone.
func show_zone_beat(title: String, subtitle: String) -> void:
	var text: String = title if subtitle == "" else "%s\n%s" % [title, subtitle]
	if _zone_tween != null and _zone_tween.is_valid():
		_zone_tween.kill()
	_zone_tween = _fade_pulse(_zone_beat, text, 0.85, 0.5, 1.8, 1.0)


## A single white exposure hit, for the still camera catching something that
## is no longer there. Harmless if a higher-priority flash is already running.
func exposure_flash(strength: float = 0.35) -> void:
	if _flash == null:
		return
	_flash.color = Color(0.92, 0.94, 1.0, strength)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.30)


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func begin_game() -> void:
	# Let mouse look through as soon as play starts; the veil is only fading.
	# The whole title subtree, not just its ColorRect, would otherwise swallow
	# motion for the length of the fade.
	_ignore_mouse(_title)
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 0.0, 1.1)
	tw.tween_callback(func() -> void:
		_title.visible = false
	)
	# Direct-call starts (tests, probes) never show the lore card, so this stays
	# a no-op there — and a hidden card can never swallow mouse look later.
	if not _lore.visible:
		return
	if _lore_fade_tween != null and _lore_fade_tween.is_valid():
		_lore_fade_tween.kill()
	_lore.modulate.a = 1.0
	_ignore_mouse(_lore)
	var lw := create_tween()
	lw.tween_property(_lore, "modulate:a", 0.0, 1.1)
	lw.tween_callback(func() -> void:
		_lore.visible = false
	)


func set_paused_ui(on: bool) -> void:
	_pause.visible = on


## F3 label state. Main gates the per-frame diagnostics string on this so the
## expensive roster walk only runs while someone can actually read it.
func debug_label_visible() -> bool:
	return _debug_label != null and _debug_label.visible


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
