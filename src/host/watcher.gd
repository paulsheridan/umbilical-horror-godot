extends "res://src/host/host.gd"
## The Watcher — a zombie that watches first, then hunts.
##
## A watcher is an ordinary Host with a patience. With direct sight of the
## drone it closes to WATCH_STANDOFF and plants; then, once the fleet's shared
## clock runs out, it hunts like the plain Host. Codified contract:
##
##   1. It approaches a drone it can see, then stops at the stand-off. While
##      passive it does not attack — it never closes inside the stand-off of
##      its own will, not even for a drone rolling straight at it.
##   2. Planted, it stands still and watches: it keeps facing the drone,
##      keeps line of sight, breathes harder (the Zone 2 profile's audio),
##      and its arms hang at the authored clip.
##   3. A drone that approaches it changes nothing: no retreat, no closing,
##      no reaction but the slow turn of its gaze.
##   4. The first time ANY watcher sees the drone, main arms one shared
##      patience clock (two minutes, plus a random 0–2 minutes). When it
##      expires every watcher turns hostile together: it closes all the way,
##      reaches, and kills on contact like the plain Host. Hostility is
##      permanent for the session; breaking line of sight only breaks the
##      pursuit, never the change.
##   5. Contact still kills while passive, under the Host's own sight rules:
##      drive inside CATCH_RANGE while it can see you (or just after it lost
##      you) and the chassis is taken.
##   6. Everything else is the zombie brain it is: authored patrol routes,
##      the curious stop, imprecise noise hunts, the flashlight beacon, the
##      motion-first sight rule, and the give-up search when the drone
##      breaks line of sight.
##
## The shipped Cold Hold population is watchers (main._spawn_zone2_hosts).
## The Host itself closes all the way and kills on contact; this file is the
## stand-off stage that precedes the shared flip to hunting.

## Emitted exactly once per body, on the first genuine sight of the drone.
## main listens on the whole fleet to arm its single shared clock.
signal sighted

## Where it plants. A passive watcher with sight closes until it is inside
## this distance of the drone, then halts and watches. The value is the old
## Host hold (STALK_KEEP + 0.3) the shipped bodies kept by accident.
const WATCH_STANDOFF := 6.8

## Switched on for the whole fleet at once when main's shared clock expires.
## Nothing in play ever clears it.
var hostile := false
var _sighted_once := false


## Sight can only be gained through _sense() -> _enter_stalk(), so the first
## stalk entry IS the first sight. The signal is one-shot for the session.
func _enter_stalk() -> void:
	super._enter_stalk()
	if not _sighted_once:
		_sighted_once = true
		sighted.emit()


## The public, test-friendly switch main pulls for the whole fleet.
func set_hostile(on: bool) -> void:
	hostile = on


## STALK is the watch while passive: planted inside the stand-off, facing the
## drone it can see. Once hostile it is the base Host brain exactly.
func _do_stalk(delta: float) -> void:
	if hostile:
		super._do_stalk(delta)
		return
	if drone == null or not is_instance_valid(drone):
		_give_up()
		return
	var to: Vector3 = drone.global_position - global_position
	to.y = 0.0
	var d := to.length()

	# Contact still kills — under the Host's own sight rules. The watcher
	# never closes inside the stand-off itself, so this only fires when the
	# player drives into it.
	if d < CATCH_RANGE and (_sees or _lost_sight_t < CONTACT_GRACE or relentless):
		_catch()
		return

	if _sees:
		_lost_sight_t = 0.0
		_last_seen_pos = drone.global_position
		if d > WATCH_STANDOFF:
			# Outside the stand-off: close at the zombie's stalking pace.
			var spd := w_stalk_close if d > STALK_FAR else w_stalk
			_seek(drone.global_position, spd)
		else:
			# Inside the stand-off: plant and watch. No attack, no retreat —
			# a drone rolling straight at it changes nothing but its gaze.
			_halt()
	else:
		# Sight broken: the Host's tail exactly. One grace second toward the
		# last place it saw motion, then a search of that memory, then patrol.
		_lost_sight_t += delta
		if _lost_sight_t < LOSE_SIGHT_TIME:
			_seek(_last_seen_pos, w_hunt)
		else:
			_enter_hunt(_last_seen_pos, 0.8)
