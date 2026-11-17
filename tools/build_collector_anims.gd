extends SceneTree
## One-off extractor: pulls the Kenney locomotion clips out of the source FBX
## scenes and writes them as standalone Animation resources the Collector
## prefab can own. Run with:
##   godot --headless --path . --script tools/build_collector_anims.gd

const SOURCES := {
	"idle": "res://assets/characters/collector/collector_idle.fbx",
	"walk": "res://assets/characters/collector/collector_walk.fbx",
	"run": "res://assets/characters/collector/collector_run.fbx",
	"jump": "res://assets/characters/collector/collector_jump.fbx",
}
const ONE_SHOT := ["jump"]
const OUT_DIR := "res://assets/characters/collector/animations"
const LIBRARY_PATH := "res://assets/characters/collector/collector_anim_library.tres"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var library := AnimationLibrary.new()
	for name: String in SOURCES:
		var scene: Node = (load(SOURCES[name]) as PackedScene).instantiate()
		var player: AnimationPlayer = scene.get_node("AnimationPlayer")
		var source: Animation = null
		for anim_name in player.get_animation_list():
			if not anim_name.contains("Targeting"):
				source = player.get_animation(anim_name)
		if source == null:
			push_error("No animation in " + SOURCES[name])
			scene.free()
			continue
		var anim: Animation = source.duplicate()
		anim.resource_name = name
		anim.loop_mode = Animation.LOOP_NONE if name in ONE_SHOT else Animation.LOOP_LINEAR
		var path := "%s/%s.tres" % [OUT_DIR, name]
		var err := ResourceSaver.save(anim, path)
		if err != OK:
			push_error("Could not save " + path)
			scene.free()
			continue
		library.add_animation(name, load(path))
		scene.free()
	var lib_err := ResourceSaver.save(library, LIBRARY_PATH)
	if lib_err != OK:
		push_error("Could not save animation library")
	print("Collector animations rebuilt: ", library.get_animation_list())
	quit()
