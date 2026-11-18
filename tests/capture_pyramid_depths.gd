extends SceneTree
## Native visual acceptance: real interior batches, enemies, rigs and clothing.
const Interior=preload("res://scripts/pyramid_interior.gd")
const Enemy=preload("res://scripts/pyramid_enemy.gd")
const Player=preload("res://scripts/player.gd")
const Shared=preload("res://tests/capture_pyramid_arsenal.gd")
class Encounter extends Node3D:
	var player: CharacterBody3D
	var defeated_ids: Dictionary={}
	func can_fight() -> bool: return false
	func same_floor(_a: Node, _b: Node) -> bool: return true
var camera: Camera3D
var interior: Node3D
var encounter: Node3D
var actors: Array[Node3D]=[]

func _initialize() -> void: call_deferred("run")
func shot(label: String, at: Vector3, target: Vector3) -> void:
	camera.global_position=at
	camera.look_at(target)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/temple_"+label+".png")
	print("CAPTURE ",label)
func run() -> void:
	create_timer(55).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	var arena:=Node3D.new()
	root.add_child(arena)
	interior=Interior.new()
	arena.add_child(interior)
	camera=Camera3D.new()
	camera.fov=62
	camera.far=700
	arena.add_child(camera)
	camera.current=true
	var p:=Player.new()
	p.live_motion_retrieval=false
	p.controls=Shared.Intent.new()
	p.add_child(p.controls)
	p.camera_rig=Shared.Aim.new()
	p.camera_rig.camera=camera
	p.add_child(p.camera_rig)
	p.spawn=Vector3(0,5,0)
	arena.add_child(p)
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	p.visual.hide()
	encounter=Encounter.new()
	encounter.player=p
	arena.add_child(encounter)
	for pair: Array in [[&"B3",["crocodile","scorpion"]],[&"B4",["ibis","construct"]],[&"B5",["cursed_warden","tomb_fighter","skeletal_mummy"]],[&"B6",["renu","tefet","sakhra"]],[&"B7",["charmer","cobra","burial_serpent"]]]:
		if "--serpent-only" in OS.get_cmdline_user_args() and pair[0]!=&"B7": continue
		var id: StringName=pair[0]
		var y: float=interior.floors[id].definition.y
		interior.update_visibility(Vector3(0,y+.1,-50),true)
		for i in range(pair[1].size()):
			var enemy:=Enemy.new()
			enemy.encounter=encounter
			enemy.opponent=p
			enemy.enemy_kind=pair[1][i]
			enemy.floor_id=id
			enemy.floor_y=y
			enemy.ceiling_y=float(interior.floors[id].definition.ceiling)
			enemy.spawn_id="capture_"+enemy.enemy_kind
			enemy.spawn=Vector3((i-(pair[1].size()-1)*.5)*4,y+.06,-50-absf(i-1)*1.5)
			interior.floors[id].add_child(enemy)
			enemy.buried=false
			enemy.visual.show()
			enemy.set_process(false)
			enemy.set_physics_process(false)
			enemy.weapon_combat.set_physics_process(false)
			enemy.visual.set_process(false)
			for j in range(15):
				enemy.visual.animate(1.0/60,Vector3.ZERO,true)
				enemy.weapon_combat.apply_pose(1.0/60)
			actors.append(enemy)
		await shot(String(id)+"_encounter",Vector3(6,y+3.2,-42),Vector3(0,y+1.3,-51))
		await shot(String(id)+"_interior",Vector3(0,y+8.5,8),Vector3(0,y+3,-62))
		for enemy in actors: enemy.queue_free()
		actors.clear()
		await process_frame
	if "--serpent-only" in OS.get_cmdline_user_args():
		print("SERPENT PIT: two native captures")
		quit()
		return
	for id: StringName in [&"U3",&"B8"]:
		var y: float=interior.floors[id].definition.y
		interior.update_visibility(Vector3(0,y+.1,-28),true)
		await shot(String(id)+"_interior",Vector3(0,y+5,-5),Vector3(0,y+2,-45))
	print("PYRAMID INTERIOR: twelve native captures")
	quit()
