extends Node
## One-shot palette export: writes every Mats() result to assets/materials as
## a shared .tres so baked scenes reference project assets instead of
## duplicating material subresources. Kept for re-export after palette edits.

const Mats := preload("res://src/mats.gd")

var NAMES := {
	"deck": Mats.deck,
	"wall": Mats.wall,
	"ceil": Mats.ceil,
	"hull": Mats.hull,
	"machine": Mats.machine,
	"cable": Mats.cable,
	"crate": Mats.crate,
	"paper": Mats.paper,
	"screen_off": Mats.screen_off,
	"bone": Mats.bone,
	"flesh": Mats.flesh,
	"shadow": Mats.shadow,
	"amber": Mats.amber,
}


func _ready() -> void:
	var dir := "res://assets/materials"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var seen := {}
	for n in NAMES:
		var mat: StandardMaterial3D = NAMES[n].call()
		if seen.has(mat.get_instance_id()):
			print("DUP %s -> %s" % [n, seen[mat.get_instance_id()]])
			continue
		seen[mat.get_instance_id()] = n
		var path := "%s/%s.tres" % [dir, n]
		var err := ResourceSaver.save(mat, path)
		print("%s -> %s (%d)" % [n, path, err])
	get_tree().quit()
