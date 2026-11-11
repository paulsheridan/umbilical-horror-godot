extends Node
## Autoload "NoiseBus" — the game's only perception channel.
## (Named NoiseBus, not Noise: "Noise" is a native Godot class and the
## autoload would shadow into it.)
##
## Everything that makes sound or recognizable motion posts here; eventually
## hosts subscribe and nothing ever reads a body's position directly.
## Loudness is roughly 0..1: quiet scrape ~0.15, walk ~0.3, sprint ~0.5,
## door cycling ~0.6, deliberate bang ~0.9.
##
## `source` identifies the body that made the sound (when it has one). Hosts
## use it to ignore each other's footsteps: two silhouettes sharing a room
## otherwise trigger one another forever. Player, drone and environment
## events may leave it null and remain audible to everyone.

signal emitted(position: Vector3, loudness: float, source: Node)

var count := 0


func emit_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	count += 1
	emitted.emit(position, clampf(loudness, 0.0, 1.0), source)


func clear() -> void:
	count = 0
