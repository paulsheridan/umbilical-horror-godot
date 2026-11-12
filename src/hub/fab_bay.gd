class_name FabBay
extends Node3D
## The fabrication bay: one sealed room the player cannot leave. The scene is
## the source of truth for geometry; this controller only owns the two
## practical-light behaviours and exposes the nodes main wires up.
##
## Layout ("FWD ◄ escape" is a later build; everything here is mid-ship):
##   west end  = pilot nook (chair, desk, dormant screen wall) + exterior door
##               (barricaded) + interior hatch on the north wall
##   center    = map table
##   north-east= fabricator
##   east      = supply lockers
##   scattered = crates, barrel, cable runs, ceiling pipes

var player_start := Vector3(4.8, 0.2, 2.8)

var pilot_chair = null
var fabricator = null
var map_table = null
var map_surface: MeshInstance3D = null
var _flicker: OmniLight3D
var _emergency: OmniLight3D
var _flicker_base := 0.85
var _fnoise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	_fnoise.frequency = 8.0
	pilot_chair = get_node_or_null("PilotChair")
	fabricator = get_node_or_null("Fabricator")
	map_table = get_node_or_null("MapTable")
	map_surface = get_node_or_null("MapSurface")
	_flicker = get_node_or_null("MapFlicker") as OmniLight3D
	_emergency = get_node_or_null("EmergencyLight") as OmniLight3D


func _process(delta: float) -> void:
	_t += delta
	if _flicker != null:
		# Slow sickly wander with rare near-outages.
		var v := _fnoise.get_noise_1d(_t * 3.0)
		var drop := sin(_t * 13.7) > 0.985
		_flicker.light_energy = _flicker_base * (0.7 + 0.3 * v) * (0.12 if drop else 1.0)
	if _emergency != null:
		_emergency.light_energy = 0.32 + 0.18 * sin(_t * 2.1)
