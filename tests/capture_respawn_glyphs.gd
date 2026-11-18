extends SceneTree
## Native visual review with real player, loot, markers and death-choice code.
const Player = preload("res://scripts/player.gd")
const Loot = preload("res://scripts/loot_authority.gd")
const Glyphs = preload("res://scripts/respawn_glyphs.gd")
const Neon = preload("res://scripts/neon.gd")
class Intent extends "res://scripts/player_input.gd":
	func _ready() -> void: pass
	func sample() -> void: pass
class Aim extends Node3D:
	var yaw:=0.0
	var pitch:=-.22
	var camera: Camera3D
	func reset_follow() -> void: pass
class Menu extends Node:
	func close_menu() -> void: pass
class Session extends Node:
	var ui:=Menu.new()
	var shop:=Menu.new()
	func _ready() -> void:
		add_child(ui)
		add_child(shop)
class Arena extends Node3D:
	var player: CharacterBody3D
	var loot: Node3D
	var dungeon_travel: Node
	var inventory_session: Node
	var start_menu: Node

func _initialize() -> void: call_deferred("run")

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/"+label+".png")

func run() -> void:
	create_timer(35).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	var arena:=Arena.new()
	root.add_child(arena)
	Neon.block(arena,Vector3(0,-.15,0),Vector3(12,.3,12))
	var camera:=Camera3D.new()
	arena.add_child(camera)
	camera.position=Vector3(3,3.1,4)
	camera.look_at(Vector3(0,.5,0))
	camera.current=true
	var p:=Player.new()
	p.live_motion_retrieval=false
	p.controls=Intent.new()
	p.add_child(p.controls)
	p.camera_rig=Aim.new()
	p.camera_rig.camera=camera
	p.add_child(p.camera_rig)
	p.spawn=Vector3(0,.03,0)
	arena.add_child(p)
	arena.player=p
	var loot:=Loot.new()
	loot.death_drop_probability=0
	arena.add_child(loot)
	loot.register_inventory(p.inventory)
	p.loot_authority=loot
	arena.loot=loot
	arena.inventory_session=Session.new()
	arena.add_child(arena.inventory_session)
	arena.start_menu=Menu.new()
	arena.add_child(arena.start_menu)
	var glyphs:=Glyphs.new()
	glyphs.world=arena
	arena.add_child(glyphs)
	p.inventory.respawn_points={"respawn":{"location":"overworld","position":[-1.4,.025,0],"yaw":0.0,"camera_yaw":0.0,"camera_pitch":-.22},"home":{"location":"overworld","position":[1.4,.025,0],"yaw":0.0,"camera_yaw":0.0,"camera_pitch":-.22}}
	p.inventory.changed.emit()
	for i in range(4): await physics_frame
	await shot("respawn_glyph_markers")
	p.receive_hit(5000,p.combat_point()+Vector3.BACK)
	await shot("respawn_choice")
	glyphs.choose("home")
	arena.queue_free()
	await process_frame
	print("RESPAWN GLYPHS: two native captures")
	quit()
