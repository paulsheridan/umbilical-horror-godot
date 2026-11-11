class_name Interactable
extends StaticBody3D
## M0 interactable: a focusable body on the "interact" layer (4) with a prompt
## and optional terse state lines. No missions yet — the point of M0 is walking
## the bay and reading the room's bones. Narration lives in the world, not in
## message text.
##
## Visual meshes are built by the level builder; this body only carries the
## collision shape + prompt + lines.

@export var prompt := "Inspect"
@export var shape_size := Vector3(0.5, 0.5, 0.5)
@export var shape_offset := Vector3.ZERO
@export var lines := PackedStringArray()

## Optional behavior hook (e.g. the pilot chair launching a sortie in M1).
## If valid, interact() calls it instead of showing flavor lines.
var on_interact := Callable()

var _idx := 0


func _ready() -> void:
	# On world layer 1 (so the player collides with it) AND layer 4 (so the
	# interact ray finds it). Mask 0 — nothing else needs to see us collide.
	collision_layer = 1 | 4
	collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = shape_size
	col.shape = box
	col.position = shape_offset
	add_child(col)


## Press E. Runs the behavior hook if wired, else returns a state line
## ("" = silent). M1+: piloting interactions are behavior, not text.
func interact() -> String:
	if on_interact.is_valid():
		on_interact.call()
		return ""
	if lines.is_empty():
		return ""
	var line := lines[_idx % lines.size()]
	_idx += 1
	return line
