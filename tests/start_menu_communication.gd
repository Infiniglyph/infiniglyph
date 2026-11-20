extends SceneTree
## Isolated Settings regression: no city simulation or loaded save is required.
const Menu=preload("res://scripts/start_menu.gd")
class Rig extends Node:
	const MIN_FOLLOW_DISTANCE=2.0
	const MAX_FOLLOW_DISTANCE=12.0
	const DEFAULT_FOLLOW_DISTANCE=5.0
	var camera:=Camera3D.new()
	var mouse_sensitivity:=.002
	var stick_sensitivity:=2.0
	var distance:=5.0
	func get_follow_distance() -> float: return distance
	func set_follow_distance(value: float) -> void: distance=value
class Combat extends Node:
	var rules: Dictionary={"camera_shake_enabled":true}
class Actor extends CharacterBody3D:
	var camera_rig:=Rig.new()
	var weapon_combat:=Combat.new()
class Graphics extends Node:
	var shadow_budget:=8
	var glow_quality:=1
	var resolution_percent:=100
	func apply_quality() -> void: pass
class Communication extends CanvasLayer:
	var text_speed:=1.0
	var voice_enabled:=true
class World extends Node:
	var graphics:=Graphics.new()
	var communication: CanvasLayer
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	root.content_scale_size=Vector2i(1280,720)
	root.size=Vector2i(1280,720)
	var world:=World.new()
	root.add_child(world)
	world.add_child(world.graphics)
	var actor:=Actor.new()
	world.add_child(actor)
	actor.add_child(actor.camera_rig)
	actor.camera_rig.add_child(actor.camera_rig.camera)
	actor.add_child(actor.weapon_combat)
	var menu:=Menu.new()
	menu.actor=actor
	world.add_child(menu)
	menu._translation_speed.value=1.7
	menu._communication_voice.button_pressed=false
	check(menu._settings_controls.has(menu._translation_speed) and menu._settings_controls.has(menu._communication_voice),"Translation speed and electronic voice controls participate in controller navigation")
	world.communication=Communication.new()
	world.add_child(world.communication)
	menu.apply_communication_settings()
	check(is_equal_approx(world.communication.text_speed,1.7) and not world.communication.voice_enabled,"Late communication startup applies already selected accessibility settings")
	var path:="user://communication_settings_fixture.cfg"
	check(menu.save_settings(path),"Communication accessibility values save with the existing configuration version")
	menu._translation_speed.value=.5
	menu._communication_voice.button_pressed=true
	check(is_equal_approx(world.communication.text_speed,.5) and world.communication.voice_enabled,"Changing Settings immediately updates active translation and voice presentation")
	check(menu.load_settings(path) and is_equal_approx(world.communication.text_speed,1.7) and not world.communication.voice_enabled,"A configuration round trip restores the real presentation settings")
	var legacy:=ConfigFile.new()
	legacy.set_value("meta","version",1)
	legacy.set_value("camera","fov",82)
	legacy.save(path)
	check(menu.load_settings(path) and is_equal_approx(world.communication.text_speed,1.0) and world.communication.voice_enabled and actor.camera_rig.camera.fov==82,"Legacy version-one configurations receive safe communication defaults")
	legacy.set_value("communication","text_speed",99)
	legacy.save(path)
	check(menu.load_settings(path) and is_equal_approx(world.communication.text_speed,2.0),"Out-of-range communication speed is bounded to the Settings range")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if "--capture" in OS.get_cmdline_user_args():
		menu._screen.show()
		menu.show_settings()
		# Focus after deferred container layout so ScrollContainer follows the
		# accessibility controls instead of an initial zero-sized focus rectangle.
		for i in range(3): await process_frame
		menu._communication_voice.grab_focus()
		for i in range(30): await process_frame; await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/communication_settings.png")
	world.free()
	print("Communication settings verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
