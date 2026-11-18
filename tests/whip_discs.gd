extends SceneTree
const Player = preload("res://scripts/player.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Database = preload("res://scripts/equipment_database.gd")
class Intent extends "res://scripts/player_input.gd":
	func _ready() -> void: pass
	func sample() -> void: pass
class Aim extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
var arena: Node3D
var p: CharacterBody3D
var q: CharacterBody3D
var camera: Camera3D
var failures := 0
var checks := 0
var hz := 60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks+=1
	if ok: print("PASS: ",title)
	else:
		failures+=1
		push_error("FAIL: "+title)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func fighter(point: Vector3) -> CharacterBody3D:
	var actor:=Player.new()
	actor.controls=Intent.new()
	actor.add_child(actor.controls)
	actor.camera_rig=Aim.new()
	actor.camera_rig.camera=camera
	actor.add_child(actor.camera_rig)
	actor.spawn=point
	actor.live_motion_retrieval=false
	arena.add_child(actor)
	actor.collision_layer=2
	actor.add_to_group("combat_targets")
	return actor

func equip(id: StringName) -> void:
	p.weapon_combat.reset()
	var item: Resource=Catalog.create(id)
	p.inventory.add_item(item)
	p.inventory.assign(&"down",item.instance_id)
	p.combat.selected_slot=&"down"
	p.combat.sheathed=false
	p.weapon_combat.sync_rig()
	p.target_lock.select(q)
	q.weapon_combat.reset()
	q.combat.blocking=false
	q.set_physics_process(false)
	q.weapon_combat.set_physics_process(false)
	q.global_position=Vector3(0,.02,5)
	p.global_position=Vector3(0,.02,0)
	p.velocity=Vector3.ZERO
	p.visual.rotation.y=0

func cast() -> void: p.weapon_combat._on_action(&"special_x",&"down")

func shot(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	camera.position=Vector3(3,2.5,6)
	camera.look_at(Vector3(0,1.1,1.3))
	camera.current=true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/"+label+".png")

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("TEST WATCHDOG");quit(2))
	arena=Node3D.new()
	root.add_child(arena)
	camera=Camera3D.new()
	arena.add_child(camera)
	var floor:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(30,1,40)
	collider.shape=box
	floor.add_child(collider)
	floor.position.y=-.5
	arena.add_child(floor)
	p=fighter(Vector3(0,.02,0))
	q=fighter(Vector3(0,.02,5))
	await frames(5)
	for id: StringName in [&"vector_disc",&"twin_vector_discs"]:
		equip(id)
		var move:=Library.move(id,&"attack_right")
		check(move.duration<.42 and move.reach<2 and move.hit_stagger==0,String(id)+" has quick close-range cuts without light stun")
		var charged:=Library.charged_move(id,&"special_rt_y",1)
		check(charged.hits.size()==1 and charged.reach==7 and charged.damage>Library.move(id,&"special_rt_y").damage,"Charged disc art strengthens a single seven-meter flight")
		cast()
		await frames(ceili(hz*.3))
		var flight: Array=p.weapon_combat.flying_discs.duplicate()
		check(flight.size()==(2 if id==&"twin_vector_discs" else 1),"Single/dual art launches the correct number of actual discs")
		check(not p.weapon_combat.rig.models[id].right.visible,"Thrown disc leaves the hand")
		await shot(String(id)+"_flight")
		var high:=0.0
		for i in range(ceili(hz*.8)):
			for disc in flight:
				if is_instance_valid(disc): high=maxf(high,disc.max_distance)
			await frames(1)
		check(high>=6.8 and high<=7.05,"Disc reaches approximately seven meters then homes to its bearer")
		check(q.health<q.weapon_combat.max_health,"Swept disc flight damages an opponent five meters away")
		check(p.weapon_combat.rig.models[id].right.visible and flight.all(func(d):return not is_instance_valid(d)),"Returning discs are reclaimed and the held model restored")
		equip(id)
		cast()
		await frames(ceili(hz*.3))
		flight=p.weapon_combat.flying_discs.duplicate()
		p.weapon_combat.cancel()
		await frames(2)
		check(flight.all(func(d):return not is_instance_valid(d)) and p.weapon_combat.rig.models[id].right.visible,"Cancellation removes flight hitboxes and restores equipment")
	# A held frontal guard and the real parry path, without custom defense code.
	equip(&"vector_disc")
	q.target_lock.select(p)
	q.combat.sheathed=false
	q.combat.blocking=true
	q.weapon_combat.parry_remaining=0
	cast()
	await frames(ceili(hz*.65))
	check(q.weapon_combat.last_blocked and q.health>990,"Existing weapon block power mitigates an incoming disc")
	equip(&"vector_disc")
	q.target_lock.select(p)
	q.combat.blocking=true
	q.weapon_combat.parry_remaining=.18
	cast()
	await frames(ceili(hz*.55))
	check(q.health==q.weapon_combat.max_health and q.weapon_combat.last_parried and p.weapon_combat.is_staggered(),"Existing parry negates disc damage and stuns the thrower")
	check(p.weapon_combat.stagger_remaining>.6 and p.weapon_combat.flying_discs.is_empty(),"Parry preserves one-second stun and cancels all owned discs")
	# Whip contact must use the cord, not the old broad sword sphere.
	var whip_id: StringName
	for entry: Dictionary in Database.all():
		if entry.family=="whip": whip_id=StringName(entry.id);break
	equip(whip_id)
	var lash: Node3D=p.weapon_combat.rig.models[whip_id].right
	check(lash.has_method("hit_candidates") and p.weapon_combat.rig.blade_segments().is_empty(),"Every whip uses the flexible lash instead of a rigid blade trail")
	q.global_position=Vector3(0,.02,2.5)
	p.weapon_combat._on_action(&"attack_right",&"down")
	var contact:=float(p.weapon_combat.active_move.hits[0])
	await frames(ceili(hz*contact))
	var a: Vector3=lash.points[0]
	var bend:=0.0
	var tip: Vector3=lash.points[-1]
	for i in range(lash.points.size()): bend=maxf(bend,lash.points[i].distance_to(a.lerp(tip,i/float(lash.points.size()-1))))
	check(a.distance_to(tip)>2 and bend>.06,"Whip extends with a curved, tapered lash at the strike")
	await shot("flexible_whip_crack")
	await frames(ceili(hz*.15))
	check(q.health<q.weapon_combat.max_health,"The visible whip cord deals close combat damage")
	equip(whip_id)
	q.global_position=Vector3(2.5,.02,.3)
	p.target_lock.clear()
	p.set_physics_process(false)
	p.visual.rotation.y=0
	var before: float=q.health
	p.weapon_combat._on_action(&"attack_right",&"down")
	await frames(ceili(hz*.65))
	check(q.health==before,"A target beside the visible lash is not hit by an invisible broad sphere")
	# Obstruction stops flight before an opponent behind a wall.
	p.set_physics_process(true)
	equip(&"vector_disc")
	var wall:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var slab:=BoxShape3D.new()
	slab.size=Vector3(5,4,.3)
	shape.shape=slab
	wall.add_child(shape)
	wall.position=Vector3(0,1.5,2.5)
	arena.add_child(wall)
	await frames(2)
	cast()
	await frames(hz)
	check(q.health==q.weapon_combat.max_health,"Opaque architecture blocks disc flight and damage")
	arena.queue_free()
	await frames(2)
	print("WHIP / DISCS ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
