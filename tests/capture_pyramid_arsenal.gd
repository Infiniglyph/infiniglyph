extends SceneTree
## Small native renderer review: real enemy/weapon scripts, no overworld load.
const Dissolve = preload("res://scripts/monster_dissolve.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/pyramid_enemy.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Neon = preload("res://scripts/neon.gd")
class Intent extends "res://scripts/player_input.gd":
	func _ready() -> void: pass
	func sample() -> void: pass
class Aim extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
class Encounter extends Node3D:
	var player: CharacterBody3D
	func can_fight() -> bool: return false
var arena: Node3D
var p: CharacterBody3D
var camera: Camera3D

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shot(label: String, point: Vector3, distance: float = 4.2) -> void:
	camera.position=point+Vector3(.8,.7,1).normalized()*distance+Vector3.UP*.6
	camera.look_at(point+Vector3.UP*1.1)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/"+label+".png")

func run() -> void:
	create_timer(35).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	arena=Node3D.new()
	root.add_child(arena)
	Neon.prepare()
	Neon.block(arena,Vector3(0,-.15,0),Vector3(20,.3,20))
	camera=Camera3D.new()
	camera.fov=45
	arena.add_child(camera)
	camera.current=true
	p=Player.new()
	p.live_motion_retrieval=false
	p.controls=Intent.new()
	p.add_child(p.controls)
	p.camera_rig=Aim.new()
	p.camera_rig.camera=camera
	p.add_child(p.camera_rig)
	p.spawn=Vector3(-3,.04,0)
	arena.add_child(p)
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	p.visual.hide()
	var encounter:=Encounter.new()
	encounter.player=p
	arena.add_child(encounter)
	for kind: String in ["jackal","skeleton"]:
		var enemy:=Enemy.new()
		enemy.encounter=encounter
		enemy.opponent=p
		enemy.enemy_kind=kind
		enemy.spawn_id="review_"+kind
		enemy.spawn=Vector3.ZERO
		encounter.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.weapon_combat.set_physics_process(false)
		for i in range(20):
			enemy.visual.animate(1.0/60,Vector3.ZERO,true)
			enemy.weapon_combat.apply_pose(1.0/60)
		await shot("pyramid_"+kind+"_design",Vector3.ZERO)
		if kind=="skeleton":
			var effect:=Dissolve.new()
			effect.victim=enemy
			arena.add_child(effect)
			await create_timer(.28).timeout
			await shot("pyramid_dissolve_design",Vector3.ZERO)
			await create_timer(.8).timeout
		elif is_instance_valid(enemy): enemy.queue_free()
		await frames(2)
	p.visual.show()
	p.position=Vector3.ZERO
	var whip_id: StringName
	for entry: Dictionary in Database.all():
		if entry.family=="whip": whip_id=StringName(entry.id);break
	for id: StringName in [whip_id,&"vector_disc",&"twin_vector_discs"]:
		var item: Resource=Catalog.create(id)
		p.inventory.add_item(item)
		p.inventory.assign(&"down",item.instance_id)
		p.combat.selected_slot=&"down"
		p.combat.sheathed=false
		p.weapon_combat.sync_rig()
		p.weapon_combat._on_action(&"attack_right",&"down")
		var time: float=p.weapon_combat.active_move.hits[0]
		for i in range(20):
			p.visual.animate(1.0/60,Vector3.ZERO,true)
			p.weapon_combat.elapsed=time
			p.weapon_combat.apply_pose(1.0/60)
		var lash: Node3D=p.weapon_combat.rig.models[id].right
		if lash.has_method("update_lash"): lash.update_lash(1.0/60,p.weapon_combat.active_move,time,Vector3.BACK)
		await shot("arsenal_"+("whip" if id==whip_id else String(id)),Vector3(0,0,.6),5.7 if id==whip_id else 4.2)
		p.weapon_combat.cancel()
	p.visual.hide()
	for i in range(3):
		var pickup:=Pickup.new()
		pickup.item_type_id=[&"monster_glyph_common",&"monster_glyph_uncommon",&"monster_glyph_rare"][i]
		arena.add_child(pickup)
		pickup.position=Vector3((i-1)*1.2,0,0)
	await shot("pyramid_remnant_tiers",Vector3(0,-.2,0),4.5)
	arena.queue_free()
	await frames(2)
	print("PYRAMID / ARSENAL: seven native design captures")
	quit()
