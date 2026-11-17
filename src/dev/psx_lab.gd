extends Node3D
## PSX Look lab: the pack's courtyard demo, driven by UMBILICAL's own manager
## and crisp options panel.
##
## Run: godot --path . res://scenes/dev/psx_lab.tscn
##
## It is the reference scene for the parts the graybox does not naturally use:
## lit, unlit, cutout (leaves, banners, grass), transparent (pool), chrome
## (gem), glow (flames, halos, beam), a flipbook sprite, billboards, and waved
## cloth/water/foliage. Every category switch and preset in the panel applies
## to it live. Changes are not saved over the game's own settings.

const DemoWorld := preload("res://addons/psx_look/demo/world.gd")
const PSXPanel := preload("res://src/ui/psx_panel.gd")

var screen: PSXScreen
var world
var panel: PanelContainer
var _kinds := {}


func _ready() -> void:
	# This is a dev scene: never write the player's look to user://psx_look.cfg.
	PSXLook.persistence = false
	PSXLook.reset_to_defaults(false)

	screen = PSXScreen.new()
	screen.name = "PSXScreen"
	add_child(screen)

	world = DemoWorld.new()
	world.name = "DemoWorld"
	screen.viewport.add_child(world)

	var env_node: WorldEnvironment = null
	for child in world.get_children():
		if child is WorldEnvironment:
			env_node = child
			break
	PSXLook.bind(self, screen, world, env_node)
	PSXLook.refresh()
	world.dress()

	_build_ui()
	_report()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)

	panel = PSXPanel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -688.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = 704.0
	ui.add_child(panel)
	panel.closed.connect(func() -> void: panel.hide())

	var help := VBoxContainer.new()
	help.position = Vector2(18, 16)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(help)
	var title := Label.new()
	title.text = "PSX LOOK LAB"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.86, 0.66, 0.42))
	help.add_child(title)
	var sub := Label.new()
	sub.text = "WASD / arrows walk  ·  drag to look  ·  F5 panel  ·  Esc quit"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	help.add_child(sub)
	var reopen := Button.new()
	reopen.text = "PSX PANEL  [F5]"
	reopen.focus_mode = Control.FOCUS_NONE
	reopen.mouse_filter = Control.MOUSE_FILTER_STOP
	reopen.pressed.connect(func() -> void: panel.visible = not panel.visible)
	help.add_child(reopen)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F5 or event.keycode == KEY_F5:
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
		get_tree().quit()


## Count what the manager converted, so a run says at a glance whether the six
## material kinds and the animated sprites are all present.
func _report() -> void:
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mat := node.material_override as ShaderMaterial
		if mat == null or mat.shader == null:
			continue
		var path := mat.shader.resource_path
		if not path.begins_with("res://addons/psx_look/"):
			continue
		var kind := path.get_file().trim_prefix("psx_").trim_suffix(".gdshader")
		_kinds[kind] = int(_kinds.get(kind, 0)) + 1
	var missing := []
	for kind in ["lit", "unlit", "cutout", "transparent", "chrome", "glow"]:
		if int(_kinds.get(kind, 0)) == 0:
			missing.append(kind)
	print("PSX LAB materials: ", _kinds)
	print("PSX LAB waves: pool=%s banners=%d leaves=%d flames=%d" % [
		world.water != null, world.banners.size(), world.leaves.size(),
		world.flames.size()])
	if missing.is_empty():
		print("PSX LAB READY")
	else:
		push_warning("PSX lab missing material kinds: %s" % str(missing))
