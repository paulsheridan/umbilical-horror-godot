extends Control
## DECK A — the hand-copy map. Two consumers, one drawing:
##   - the fullscreen overlay (E at the map table)
##   - the physical paper on the table itself, via a live SubViewport texture
##
## Never a live map of *where things are*: compartments ink in where a drone
## has been, radar sweeps hand-dot the walls they've touched, and objectives
## are named markers (never the monster, never the player's live position).

const SHIP_W := 56.0   # x -21..35 (Processor wing added)
const SHIP_H := 42.0   # z -36..6
const SHIP_CENTER := Vector2(7.0, -15.0)

# Hand-traced compartments, mirroring the ship builder.
const ROOMS := [
	{"n": "FAB BAY", "x0": -7.0, "x1": 7.0, "z0": -5.0, "z1": 5.0, "zone": "bay"},
	{"n": "HATCH", "x0": -3.4, "x1": -1.2, "z0": -6.4, "z1": -5.4, "zone": "corridor"},
	{"n": "LEG A", "x0": -3.4, "x1": -1.2, "z0": -14.4, "z1": -6.4, "zone": "corridor"},
	{"n": "BEND", "x0": -3.4, "x1": 1.4, "z0": -16.4, "z1": -14.4, "zone": "bend"},
	{"n": "LEG C", "x0": -1.4, "x1": 1.0, "z0": -25.6, "z1": -16.4, "zone": "corridor"},
	{"n": "JUNCTION", "x0": -4.6, "x1": 4.6, "z0": -32.6, "z1": -25.6, "zone": "junction"},
	{"n": "SPUR", "x0": 4.6, "x1": 9.0, "z0": -31.4, "z1": -28.4, "zone": "spur"},
	{"n": "RING N", "x0": 9.0, "x1": 21.0, "z0": -31.4, "z1": -28.4, "zone": "annex"},
	{"n": "RING E", "x0": 19.2, "x1": 21.0, "z0": -28.4, "z1": -16.0, "zone": "annex"},
	{"n": "RING S", "x0": 6.2, "x1": 19.2, "z0": -17.6, "z1": -16.0, "zone": "annex"},
	{"n": "RING W", "x0": 4.6, "x1": 6.2, "z0": -28.4, "z1": -16.0, "zone": "annex"},
	{"n": "CAFETERIA", "x0": 6.2, "x1": 19.2, "z0": -28.4, "z1": -17.6, "zone": "cafeteria"},
	{"n": "GALLEY STUB", "x0": -8.4, "x1": -4.6, "z0": -30.0, "z1": -28.4, "zone": "galley"},
	{"n": "GALLEY", "x0": -20.4, "x1": -8.4, "z0": -34.4, "z1": -24.0, "zone": "galley"},
	{"n": "COLD", "x0": -19.8, "x1": -17.2, "z0": -33.8, "z1": -31.6, "zone": "coldroom"},
	{"n": "BERTH LINK", "x0": 7.6, "x1": 9.6, "z0": -16.0, "z1": -13.0, "zone": "berths"},
	{"n": "BERTH LINK", "x0": 16.6, "x1": 18.6, "z0": -16.0, "z1": -13.0, "zone": "berths"},
	{"n": "BERTH HALL", "x0": 7.0, "x1": 21.0, "z0": -13.0, "z1": -10.4, "zone": "berths"},
	{"n": "BERTH 1", "x0": 7.4, "x1": 10.4, "z0": -10.4, "z1": -6.0, "zone": "berths"},
	{"n": "BERTH 2", "x0": 11.2, "x1": 14.2, "z0": -10.4, "z1": -6.0, "zone": "berths"},
	{"n": "BERTH 3", "x0": 15.0, "x1": 18.0, "z0": -10.4, "z1": -6.0, "zone": "berths"},
	{"n": "OSSUARY", "x0": 18.8, "x1": 21.0, "z0": -10.4, "z1": -6.0, "zone": "berths"},
	{"n": "PROC HALL", "x0": 21.0, "x1": 28.0, "z0": -13.0, "z1": -10.4, "zone": "processor"},
	{"n": "PROCESSOR", "x0": 28.0, "x1": 33.0, "z0": -15.4, "z1": -8.0, "zone": "processor"},
]

var data: Dictionary = {}

# Layout (recomputed by fit_to).
var _scale := 12.0
var _center := Vector2(660.0, 392.0)
var _big := true


## Fit the deck to a host rect (the overlay or the table viewport).
func fit_to(w: float, h: float) -> void:
	_big = w > 600.0
	_scale = minf(w * 0.78 / SHIP_W, h * 0.78 / SHIP_H)
	_center = Vector2(w * 0.55, h * 0.5) - SHIP_CENTER * _scale
	queue_redraw()


func _p(pos: Vector3) -> Vector2:
	return _center + Vector2(pos.x, pos.z) * _scale


func _ink(a: float) -> Color:
	return Color(0.80, 0.72, 0.55, a)


func _draw() -> void:
	# Paper (only when drawn onto the table; the overlay stays transparent).
	if not _big:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.14, 0.11, 0.94))
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.35, 0.31, 0.24, 0.9), false, 1.0)

	var visited: Dictionary = data.get("visited", {"bay": true})
	var stage: int = data.get("stage", 0)
	var installed: bool = data.get("camera_installed", false)

	if _big:
		draw_string(ThemeDB.fallback_font, Vector2(30, 30), "DECK A — hand copy",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _ink(0.85))

	for room in ROOMS:
		var r := Rect2(
			Vector2(room["x0"] * _scale, room["z0"] * _scale) + _center,
			Vector2((room["x1"] - room["x0"]) * _scale, (room["z1"] - room["z0"]) * _scale))
		var known: bool = visited.has(room["zone"])
		if known:
			draw_rect(r, _ink(0.55), false, 1.4 if _big else 1.0)
			if _big and r.size.x > 60.0:
				var mid := r.position + r.size * 0.5
				draw_string(ThemeDB.fallback_font, mid + Vector2(-r.size.x * 0.35, 4),
						room["n"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(0.9))
		else:
			for i in range(0, int(r.size.x / 6.0)):
				var x := r.position.x + i * 6.0
				draw_line(Vector2(x, r.position.y), Vector2(x + 4, r.position.y + r.size.y),
						_ink(0.12), 1.0)
			draw_rect(r, _ink(0.15), false, 1.0)

	# Radar ink: every wall the sweeps have touched, hand-dotted.
	for p in data.get("charted", []):
		var cp := _p(p)
		draw_rect(Rect2(cp - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), _ink(0.30))

	# The galley door: sealed or ground-open. (Never shows anything alive.)
	var dp := _p(Vector3(-8.65, 0, -29.2))
	var open: bool = data.get("door_open", false)
	draw_line(dp + Vector2(0, -8), dp + Vector2(0, 8),
			Color(0.55, 0.85, 0.55, 0.95) if open else Color(0.85, 0.3, 0.22, 0.95), 2.0)

	# Rations marker (the pantry was always on the map).
	if data.get("rations_pending", false):
		var fp := _p(Vector3(-12.6, 0, -31.0))
		draw_rect(Rect2(fp - Vector2(3, 3), Vector2(6, 6)), _ink(0.95))
		if _big:
			draw_string(ThemeDB.fallback_font, fp + Vector2(7, 3), "RAT",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(0.95))

	# Camera wreck site: once the module has somewhere to be recovered.
	if stage >= 1 and not installed:
		var sp := _p(data.get("site", Vector3.ZERO))
		draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), _ink(1.0), false, 1.5)
		if _big:
			draw_string(ThemeDB.fallback_font, sp + Vector2(9, 3), "CAM",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(1.0))

	# The dock: home.
	var dk := _p(data.get("dock", Vector3.ZERO))
	draw_line(dk + Vector2(-5, 0), dk + Vector2(5, 0), _ink(0.95), 1.4)
	draw_line(dk + Vector2(0, -5), dk + Vector2(0, 5), _ink(0.95), 1.4)
	if _big:
		draw_string(ThemeDB.fallback_font, dk + Vector2(7, 3), "DOCK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(0.95))

	if _big:
		draw_string(ThemeDB.fallback_font, Vector2(30, 60), "N ^",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _ink(0.8))
		draw_line(Vector2(30, 700), Vector2(30 + 5 * _scale, 700), _ink(0.8), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(34, 690), "5 m",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(0.8))
		draw_string(ThemeDB.fallback_font, Vector2(30, 665),
				"compartments fill in where a drone has been; sweeps ink the walls",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink(0.5))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(10, 16), "DECK A",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _ink(0.85))
		draw_line(Vector2(10, size.y - 12), Vector2(10 + 5 * _scale, size.y - 12),
				_ink(0.8), 1.5)
