extends SceneTree
## Lightweight native capture using the actual enemy, rig and wearable scripts.
const Shared = preload("res://tests/capture_pyramid_arsenal.gd")
const Enemy = preload("res://scripts/pyramid_enemy.gd")
const Player = preload("res://scripts/player.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Moves = preload("res://scripts/falcon_moves.gd")
const Neon = preload("res://scripts/neon.gd")
class Encounter extends Node3D:
	var player: CharacterBody3D
	func can_fight() -> bool: return false
	func same_floor(_actor: Node, _target: Node) -> bool: return true
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func shot(label: String, from: Vector3=Vector3(2.8,2.1,4.8)) -> void:
	camera.position=from
	camera.look_at(Vector3(0,1.05,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/"+label+".png")
func run() -> void:
	create_timer(45).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	var arena:=Node3D.new()
	root.add_child(arena)
	Neon.block(arena,Vector3(0,-.2,0),Vector3(20,.4,20))
	camera=Camera3D.new()
	camera.fov=46
	arena.add_child(camera)
	camera.current=true
	var p:=Player.new()
	p.live_motion_retrieval=false
	p.controls=Shared.Intent.new()
	p.add_child(p.controls)
	p.camera_rig=Shared.Aim.new()
	p.camera_rig.camera=camera
	p.add_child(p.camera_rig)
	p.spawn=Vector3(5,.04,0)
	arena.add_child(p)
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	p.visual.hide()
	var encounter:=Encounter.new()
	encounter.player=p
	arena.add_child(encounter)
	for kind: String in ["falcon","winged_skeleton","archer"]:
		var enemy:=Enemy.new()
		enemy.encounter=encounter
		enemy.opponent=p
		enemy.enemy_kind=kind
		enemy.floor_id=&"B2"
		enemy.ceiling_y=16
		enemy.spawn_id="capture_"+kind
		enemy.spawn=Vector3.ZERO
		encounter.add_child(enemy)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.weapon_combat.set_physics_process(false)
		enemy.visual.set_process(false)
		for i in range(20):
			enemy.visual.animate(1.0/60,Vector3.ZERO,true)
			enemy.weapon_combat.apply_pose(1.0/60)
		if is_instance_valid(enemy.visual.wings): enemy.visual.wings.pose(.8,false,false)
		await shot("b2_"+kind+"_rest")
		if kind=="falcon":
			await shot("b2_falcon_back",Vector3(2.5,2.1,-4.5))
			enemy.visual.wings.pose(1,true,true)
			enemy.weapon_combat._begin(Moves.move("falcon",&"special_x"))
			for i in range(20):
				enemy.visual.animate(1.0/60,Vector3.ZERO,false)
				enemy.weapon_combat.elapsed=.48
				enemy.weapon_combat.apply_pose(1.0/60)
			await shot("b2_falcon_wing_slash",Vector3(.5,2.0,6))
			if "--sentinel-only" in OS.get_cmdline_user_args():
				print("FALCON SENTINEL: three native captures")
				quit()
				return
		enemy.queue_free()
		await process_frame
	p.position=Vector3.ZERO
	p.visual.show()
	for pair: Array in [[&"falcon_sentinel_mantle",&"body"],[&"skyguard_tassets",&"legs"],[&"eye_of_horus_seal",&"ring1"]]:
		var item: Resource=Catalog.create(pair[0])
		p.inventory.add_item(item)
		p.inventory.assign(pair[1],item.instance_id)
	p.combat.sheathed=true
	p.weapon_combat.sync_rig()
	for model: Dictionary in p.weapon_combat.rig.models.values():
		model.right.hide()
		model.left.hide()
		model.stowed.hide()
	p.visual.animate(1.0/60,Vector3.ZERO,true)
	await shot("b2_wearable_copies")
	await shot("b2_wearable_copies_back",Vector3(2.5,2.1,-4.5))
	print("FALCON SENTINELS: seven native captures")
	quit()
