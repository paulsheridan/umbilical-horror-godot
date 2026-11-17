extends Node3D
## One droplet in the Collector's vomit spray. It is a ballistic, collision-free
## glob: the Collector launches dozens of these per attack and each one simply
## falls and frees. The spray never slows or stops the player and leaves no
## decal behind.

const GRAVITY := 9.0

var _velocity := Vector3.ZERO
var _life := 1.0
var _size := 1.0


func spray(origin: Vector3, velocity: Vector3, life: float, size: float) -> void:
	global_position = origin
	_velocity = velocity
	_life = life
	_size = size
	scale = Vector3.ONE * size
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	rotate_y(delta * 7.0)
