extends SceneTree
const Interior=preload("res://scripts/pyramid_interior.gd")
const Boss=preload("res://scripts/lorai.gd")
const Player=preload("res://scripts/player.gd")
const Moves=preload("res://scripts/lorai_moves.gd")
const Database=preload("res://scripts/equipment_database.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Shared=preload("res://tests/capture_pyramid_arsenal.gd")
class Encounter extends Node3D:
	func can_fight() -> bool: return false
	func same_floor(_a: Node, _b: Node) -> bool: return true
var camera: Camera3D
var interior: Node3D
var boss: CharacterBody3D
var p: CharacterBody3D
func _initialize() -> void: call_deferred("run")
func shot(label: String, at: Vector3, target: Vector3) -> void:
	camera.global_position=at
	camera.look_at(target)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/ahkmet_"+label+".png")
	print("CAPTURE ",label)
func run() -> void:
	create_timer(60).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	var arena:=Node3D.new()
	root.add_child(arena)
	interior=Interior.new()
	arena.add_child(interior)
	camera=Camera3D.new()
	camera.fov=65
	camera.far=700
	arena.add_child(camera)
	camera.current=true
	p=Player.new()
	p.live_motion_retrieval=false
	p.controls=Shared.Intent.new()
	p.add_child(p.controls)
	p.camera_rig=Shared.Aim.new()
	p.camera_rig.camera=camera
	p.add_child(p.camera_rig)
	arena.add_child(p)
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	p.global_position=Vector3(0,-143.94,-24)
	var encounter:=Encounter.new()
	arena.add_child(encounter)
	boss=Boss.new()
	boss.encounter=encounter
	boss.opponent=p
	interior.floors[&"B8"].add_child(boss)
	boss.set_physics_process(false)
	boss.weapon_combat.set_physics_process(false)
	interior.update_visibility(Vector3(0,-143.94,-48),true)
	await shot("mounted",Vector3(18,-130,-23),Vector3(0,-137.5,-48))
	await shot("pharaoh",Vector3(5,-132,-37),Vector3(0,-134.1,-43))
	boss.visual.pose({},0,0,3.1)
	await shot("welcome",Vector3(4,-130.5,-37),Vector3(0,-132.2,-42.5))
	boss.visual.pose({},0,0,4.0)
	await shot("union",Vector3(8,-129,-30),Vector3(0,-132,-42))
	boss.visual.pose({},0,2,0)
	await shot("ascendant",Vector3(19,-127,-22),Vector3(0,-136,-46))
	boss.attack_goal=Vector3(0,-142.7,-34)
	boss.visual.pose(Moves.move("annihilation"),1.4,2,0)
	await shot("staff_attack",Vector3(19,-127,-22),Vector3(0,-135,-45))
	await shot("throne_room",Vector3(34,-123,12),Vector3(0,-136,-80))
	boss.hide()
	p.global_position=Vector3(0,-143.94,-45)
	for id: StringName in [&"pharaoh_vile_nemes",&"pharaoh_vile_mantle",&"pharaoh_vile_bracers",&"pharaoh_vile_greaves"]:
		var item: Resource=Catalog.create(id)
		p.inventory.add_item(item)
		p.inventory.assign(StringName(Database.get_item(id).slot),item.instance_id)
	p.visual.sync_clothing(p.inventory)
	await shot("royal_gear",Vector3(2.1,-142.4,-40),Vector3(0,-142.9,-45))
	print("AHKMET NATIVE: eight captures")
	quit()
