extends Node
## Autoload "GameState" — single source of truth.
## Act state, sortie state, life-support meters, run clock.
## Scenes read from here; they never cache values.

signal meters_changed

enum Sortie { IDLE, PILOTING }

# Meters are percent/hr budgets — deliberately slow in M0 so a shown 10-minute
# session can stay ahead of them, but the pressure is on the clock already.
const O2_RATE := 0.55    # % per hour
const H2O_RATE := 0.80   # % per hour
const KCAL_RATE := 0.90  # % per hour

var running := false
var paused := false
var map_open := false   # the hand-copy map is up; the player's hands are busy
var sortie: int = Sortie.IDLE

var o2 := 91.0
var h2o := 64.0
var kcal := 55.0
var clock_hours := 0.0


func _process(delta: float) -> void:
	if not running:
		return
	var hours := delta / 3600.0
	clock_hours += hours
	o2 = maxf(o2 - O2_RATE * hours, 0.0)
	h2o = maxf(h2o - H2O_RATE * hours, 0.0)
	kcal = maxf(kcal - KCAL_RATE * hours, 0.0)
	meters_changed.emit()


func meters_text() -> String:
	return "O2 %3.0f%%   H2O %3.0f%%   KCAL %3.0f%%" % [o2, h2o, kcal]
