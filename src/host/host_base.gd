extends CharacterBody3D
## Shared body for the ship's hostile bodies: the patrol Host and the Stalker.
##
## Both are CharacterBody3D rigs under the same fleet rules: one "hosts" group,
## one catch signal, one hearing test, one locomotion primitive. The state
## machines are deliberately NOT shared — each body keeps its own State enum
## and its own _do_* dispatch, because their modes genuinely differ (the Host
## escalates through patrol/curious/hunt/stalk, the Stalker lurks, lunges and
## folds into ambush). Everything here is the machinery those two machines used
## to copy from each other, and had already begun to drift apart on.

## Emitted once per catch. Main binds it to its own reel bookkeeping.
signal drone_caught

const GRAVITY := 12.0

var drone = null
var waypoints: Array = []

## Hearing scale: audible radius ≈ loudness * this. The Host overrides it in
## configure_aggressive(); the Stalker assigns its own authored value in _ready.
var hearing_mult := 20.0

## Debug vision: a ghosted body still patrols but cannot see, hear or catch the
## fleet. Main sets this on its developer toggle; normal play never does.
var ghosted := false

## Index into the owning body's OWN State enum. Every subclass assigns this from
## its own enum, so the numbers only mean anything inside that script.
var state: int = 0

var _wp := 0
var _rest := 0.0
var _commanded := Vector3.ZERO   # velocity we ASKED for (move_and_slide may
                                 # zero the real one against a wall)
var _last_seen_pos := Vector3.ZERO
var _lost_sight_t := 0.0
var _sees := false
var _caught := false
## The drone this body latched onto. Main keeps only the first catch in a reel
## window and drops the rest; comparing the bound drone lets a spurned catcher
## un-latch instead of sitting dead for the rest of the run.
var _caught_drone = null
var _hum: AudioStreamPlayer3D = null

# Stuck watch: straight-line seek can still wedge on a corner. If the body is
# pressing but not traveling, re-route instead of standing there forever.
var _stuck_t := 0.0
var _stuck_last := Vector3.ZERO
var _stuck_run := 0

## Untagged-environment echo closer than this is the body's own wet steps. The
## Stalker's shorter reach is part of its tuned noise profile.
var _noise_self_radius := 1.2

var _rng := RandomNumberGenerator.new()


## Shared _ready prologue: rng, group and collision filters. Each subclass calls
## this first in its _ready(), before it resolves its own rig.
func _body_ready() -> void:
	_rng.randomize()
	collision_layer = 8
	collision_mask = 1 | 4
	add_to_group("hosts")
	floor_snap_length = 0.5


## Shared physics tail: gravity and the actual slide. The subclass owns its own
## state dispatch, stuck watch and presentation around this call.
func _move_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()


# --------------------------------------------------------------------------
# Perception
# --------------------------------------------------------------------------

## True while the chassis has its fitted flashlight switched on. The beam is
## read as a threat signal, not as a light meter: no shadow-casting needed.
## Low cover hides a dark machine; it does not hide a lit beam.
func _drone_lit() -> bool:
	if drone == null or not is_instance_valid(drone):
		return false
	return bool(drone.flashlight_installed) and bool(drone.flashlight_on)


## The deafness preamble every body shares. Hosts never hear each other: two of
## them in one room otherwise lock into an endless mutual-investigate loop, so
## a host-sourced event is invisible to every other host (the scanner and the
## player's dread still see it). A ghosted body hears nothing at all. Returns
## true only for a real, in-range noise this body should react to.
func _noise_audible(position: Vector3, loudness: float, source) -> bool:
	if ghosted:
		return false
	if source != null:
		if not is_instance_valid(source):
			return false
		if source == self or source.is_in_group("hosts"):
			return false
	var d := position.distance_to(global_position)
	if d < _noise_self_radius:
		return false   # its own wet steps (untagged environment echo)
	if d > loudness * hearing_mult:
		return false
	return true


# --------------------------------------------------------------------------
# Catch plumbing
# --------------------------------------------------------------------------

## A catch whose reel was dropped must not stay latched: if main has since
## rebound our senses to a different chassis, that catch never landed. Called at
## the top of each body's _sense().
func _unlatch_spurned_catch() -> void:
	if _caught and drone != _caught_drone:
		_caught = false


## Latch the catch and tell main. A ghosted body must never catch: F4's
## documented contract is that hostile bodies ignore the fleet entirely.
func _catch() -> void:
	if _caught:
		return
	if ghosted:
		return
	_caught = true
	_caught_drone = drone
	_halt()
	drone_caught.emit()


## The fleet absorbed the loss: a surviving chassis carries the link, so this
## body has not ended the run. Let it resume its own hunt instead of freezing on
## the kill; each subclass's _give_up() decides what resuming means.
func release_catch() -> void:
	_give_up()


## Virtual: the body's own "drop the chase" transition. Both subclasses define
## it; a bare base body has no state machine to return to.
func _give_up() -> void:
	pass


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_commanded = Vector3.ZERO


func _seek(target: Vector3, speed: float) -> void:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() > 0.35:
		var dir := flat.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		_commanded = Vector3(velocity.x, 0.0, velocity.z)
	else:
		_halt()


func _flat_dist(target: Vector3) -> float:
	var flat := target - global_position
	flat.y = 0.0
	return flat.length()


func _yaw_to(target: Vector3) -> float:
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return rotation.y
	return atan2(-flat.x, -flat.z)


func _nearest_wp() -> int:
	var best := 0
	var best_d := INF
	for i in waypoints.size():
		var d := _flat_dist(waypoints[i])
		if d < best_d:
			best_d = d
			best = i
	return best
