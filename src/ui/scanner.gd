extends Control
## Movement scanner v1 — radar is the primary display until the video module
## is recovered; afterwards it shrinks to an inset so the live feed owns the
## screen. The sweep pings walls as decaying echo ghosts; NoiseBus events show
## as blips.

const RANGE := 16.0          # meters of echo reach
const PX_PER_M := 7.0        # bigger, finer picture
const SWEEP_TIME := 2.4      # seconds per revolution
const ECHO_LIFE := 20.0
const BLIP_LIFE := 6.0
const MAX_ECHOES := 600

## Emitted for every actual wall return (already deduped locally). Main uses
## this to chart the ship permanently onto the map table.
signal echo_recorded(position: Vector3)

var drone: Node3D = null
var anchor_pos := Vector3.ZERO

var echoes: Array = []       # {"pos": Vector3, "t": float}
var blips: Array = []        # {"pos": Vector3, "t": float}
var masses: Array = []       # {"node": Node3D, "radius": float} — big bodies
var sweep := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # never block the mouse look
	NoiseBus.emitted.connect(_on_noise)


func _on_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	if drone == null or not visible:
		return
	# Your own motor is not a contact: don't paint the radar with your engine.
	if source != null and source == drone:
		return
	# Some bodies are read as a physical mass instead of a noise blip.
	if source != null and source.get("radar_blips") == false:
		return
	if drone.global_position.distance_to(position) < RANGE:
		blips.append({"pos": position, "t": 0.0, "loud": loudness})
		Sfx.play("ping", Sfx.CENTER, -20.0, randf_range(0.92, 1.12))


func _add_echo(position: Vector3) -> void:
	# Damp duplicates: the same wall face swept at high fps must not spam.
	for e in echoes:
		if float(e["t"]) < 1.0 and (e["pos"] as Vector3).distance_to(position) < 0.5:
			return
	echoes.append({"pos": position, "t": 0.0})
	echo_recorded.emit(position)
	if echoes.size() > MAX_ECHOES:
		echoes.pop_front()


## Register a body that reads as a moving mass instead of discrete noise
## blips. The scanner draws it as a broad, slow pulse; the node's position is
## read live each frame.
func add_mass(node: Node3D, radius := 1.8) -> void:
	for m in masses:
		if m["node"] == node:
			m["radius"] = radius
			return
	masses.append({"node": node, "radius": radius})


func remove_mass(node: Node3D) -> void:
	masses = masses.filter(func(m): return m["node"] != node)


func _process(delta: float) -> void:
	if drone == null or not visible:
		return
	sweep = fposmod(sweep + delta * TAU / SWEEP_TIME, TAU)
	var space := drone.get_world_3d().direct_space_state
	var origin: Vector3 = drone.global_position + Vector3(0, 0.5, 0)
	# Six rays per frame along the beam: a denser, higher-fidelity echo field.
	for i in 6:
		var a := sweep + 0.045 * float(i)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(
				origin, origin + dir * RANGE, 1)
		var hit := space.intersect_ray(q)
		if hit.size() > 0:
			_add_echo(hit.position)
	for e in echoes:
		e["t"] = float(e["t"]) + delta
	echoes = echoes.filter(func(e): return float(e["t"]) < ECHO_LIFE)
	for b in blips:
		b["t"] = float(b["t"]) + delta
	blips = blips.filter(func(b): return float(b["t"]) < BLIP_LIFE)
	masses = masses.filter(func(m): return is_instance_valid(m["node"]))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 10.0
	if r < 20.0:
		return
	var ppm := r / RANGE   # the ring always equals full scanner range
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.0, 0.015, 0.008, 0.78))
	draw_circle(c, r, Color(0.008, 0.05, 0.03, 0.92))
	draw_arc(c, r, 0.0, TAU, 72, Color(0.25, 0.7, 0.4, 0.5), 1.2)
	for ring_m in [5.0, 10.0, 15.0]:
		var rr: float = ring_m * ppm
		if rr < r:
			draw_arc(c, rr, 0.0, TAU, 64, Color(0.25, 0.7, 0.4, 0.16), 1.0)
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0.25, 0.7, 0.4, 0.12), 1.0)
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0.25, 0.7, 0.4, 0.12), 1.0)
	draw_circle(c, 2.0, Color(0.25, 0.7, 0.4, 0.4))

	if drone == null:
		return
	var dpos: Vector3 = drone.global_position

	for e in echoes:
		var d: Vector3 = (e["pos"] as Vector3) - dpos
		var sp := c + Vector2(d.x, d.z) * ppm
		if (sp - c).length() > r:
			continue
		var a := clampf(1.0 - float(e["t"]) / ECHO_LIFE, 0.0, 1.0) * 0.5
		draw_circle(sp, 2.6, Color(0.35, 0.95, 0.55, a))

	for b in blips:
		var d: Vector3 = (b["pos"] as Vector3) - dpos
		var sp := c + Vector2(d.x, d.z) * ppm
		if (sp - c).length() > r:
			continue
		var a := clampf(1.0 - float(b["t"]) / BLIP_LIFE, 0.0, 1.0)
		draw_circle(sp, 4.3, Color(0.95, 0.9, 0.25, 0.25 + 0.55 * minf(a, 1.0)))

	# Big bodies read as a broad, slow mass, not a noise blip. The pulse keeps
	# it visibly alive without turning it into a target marker.
	for m in masses:
		var node = m["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var md: Vector3 = node.global_position - dpos
		var msp := c + Vector2(md.x, md.z) * ppm
		if (msp - c).length() > r:
			continue
		var rscale := 1.0
		var rs = node.get("radar_mass_scale")
		if rs != null:
			rscale = float(rs)
		var rad: float = float(m["radius"]) * ppm * rscale \
				* (1.0 + 0.06 * sin(sweep * 3.0))
		# Pale aura around a dark core: a body, not a noise return. The yellow
		# blips stay sharply different.
		draw_circle(msp, rad, Color(0.70, 0.82, 0.66, 0.10))
		draw_circle(msp + Vector2(rad * 0.16, -rad * 0.10), rad * 0.72,
				Color(0.74, 0.86, 0.70, 0.16))
		draw_circle(msp, rad * 0.36, Color(0.015, 0.035, 0.02, 0.60))
		draw_arc(msp, rad, 0.0, TAU, 20, Color(0.80, 0.90, 0.75, 0.52), 1.4)

	# Heading arrow (screen: +x east, +y south; forward = -basis.z).
	var f: Vector3 = -drone.global_transform.basis.z
	var fv := Vector2(f.x, f.z).normalized() * minf(40.0, r * 0.18)
	draw_line(c, c + fv, Color(0.9, 0.95, 0.9, 0.9), 2.6)
	draw_circle(c, 4.0, Color(0.9, 0.95, 0.9, 0.9))

	# Direction to the dock anchor: the homeward line when lost.
	var ad: Vector3 = anchor_pos - dpos
	var av := Vector2(ad.x, ad.z)
	if av.length() > 0.5:
		var pt := c + av.normalized() * minf(av.length() * ppm, r - 16.0)
		draw_line(c, pt, Color(0.85, 0.5, 0.2, 0.65), 1.6)
		var font := ThemeDB.fallback_font
		draw_string(font, pt + Vector2(4.0, -4.0), "DOCK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.85, 0.5, 0.2, 0.85))

	draw_string(ThemeDB.fallback_font, Vector2(c.x - 5.0, c.y - r + 13.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.6, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(c.x - 5.0, c.y + r - 5.0), "S",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.6, 0.8))
