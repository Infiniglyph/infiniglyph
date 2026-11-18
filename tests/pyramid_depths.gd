extends SceneTree
const Types=preload("res://scripts/pyramid_bestiary.gd")
const Moves=preload("res://scripts/pyramid_depth_moves.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Database=preload("res://scripts/equipment_database.gd")
const Store=preload("res://scripts/inventory_store.gd")
const Preview=preload("res://scripts/equipment_preview.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var encounter: Node3D
var hz:=60
var checks:=0
var failures:=0

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
func frames(n: int=2) -> void:
	for i in range(n):
		await physics_frame
		await process_frame
func freeze() -> void:
	for e in encounter.enemies:
		if not is_instance_valid(e): continue
		e.set_process(false)
		e.set_physics_process(false)
		e.weapon_combat.set_physics_process(false)
		e.controls.active=false
		e.weapon_combat.cancel()
func find(kind: String) -> CharacterBody3D:
	for e in encounter.enemies:
		if is_instance_valid(e) and not e.dead and e.enemy_kind==kind: return e
	return null
func floor_visit(id: StringName) -> void:
	encounter.reset_run()
	p.global_position=travel.interior.floors[id].spawn_anchor.position
	p.velocity=Vector3.ZERO
	p.weapon_combat.reset()
	p.fall_damage.reset()
	travel.interior.update_visibility(p.global_position,true)
	encounter.ensure_spawned(id)
	freeze()
	await frames(2)
	freeze()
func arrange(e: CharacterBody3D, point: Vector3, player_point: Vector3) -> void:
	e.global_position=point
	p.global_position=player_point
	p.velocity=Vector3.ZERO
	p.weapon_combat.reset()
	p.combat.reset()
	e.target_lock.select(p)
	p.target_lock.select(e)
func lethal(e: CharacterBody3D) -> void:
	e.receive_combat_hit(9999,e.combat_point()+Vector3.BACK,p,{"action":"attack_right","parryable":false})

func run() -> void:
	create_timer(90).timeout.connect(func():push_error("DEPTHS WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	var input:=Intent.new()
	root.add_child(input)
	p.controls=input
	world.camera_rig.controls=input
	world.inventory_session.controls=input
	p.visual.retrieval.enabled=false
	world.loot.death_drop_probability=0
	travel=world.dungeon_travel
	encounter=travel.encounters
	await frames(4)
	travel._set_location(travel.pyramid_id)
	p.set_physics_process(false)
	var built:=true
	var clear_stairs:=true
	for floor_id: StringName in travel.interior.floors:
		var floor: Node3D=travel.interior.floors[floor_id]
		built=built and is_instance_valid(floor.dressing) and floor.dressing.batch.mesh_instance.mesh.get_surface_count()<=2 and not floor.dressing.features.is_empty()
		for volume: Dictionary in floor.dressing.batch.volumes:
			var shape: Shape3D=volume.collider.shape
			if not shape is BoxShape3D: continue
			var at: Vector3=volume.transform.origin
			var area:=Rect2(Vector2(at.x,at.z)-Vector2(shape.size.x,shape.size.z)*.5,Vector2(shape.size.x,shape.size.z))
			for hole: Rect2 in floor.floor_holes+floor.ceiling_holes:
				if area.intersects(hole): clear_stairs=false
	check(built,"All 17 floors receive original batched thematic furnishings")
	check(clear_stairs,"New solid props leave every stair aperture clear")
	var total:=0
	var kinds: Dictionary={}
	for data: Dictionary in travel.interior.definitions:
		var id: StringName=data.id
		await floor_visit(id)
		var roster: Array=encounter.roster_for(id)
		total+=roster.size()
		check(encounter.spawned_floors.has(id)==(id==&"B8" or not roster.is_empty()),"Floor population is lazy and matches its authored roster: "+String(id))
		var safe:=true
		for e in encounter.enemies:
			if not is_instance_valid(e): continue
			kinds[e.enemy_kind]=true
			var shape:=CapsuleShape3D.new()
			shape.radius=.28
			shape.height=.85 if e.traits.get("beast",false) and e.enemy_kind!="charm_obelisk" else 1.85
			var q:=PhysicsShapeQueryParameters3D.new()
			q.shape=shape
			q.transform.origin=e.spawn+Vector3.UP*(shape.height*.5+.03)
			q.collision_mask=9
			q.exclude=[e.get_rid(),p.get_rid()]
			if not p.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():
				print("BLOCKED SPAWN ",id," ",e.spawn_id," ",e.spawn)
				safe=false
		check(safe,"Enemies have clear supported starting volumes: "+String(id))
	check(total>90 and kinds.size()>=25,"Upper temples and B1-B7 contain a complete varied roster")
	await floor_visit(&"B8")
	check(encounter.roster_for(&"B8").is_empty() and is_instance_valid(encounter.b8.boss),"Bottom arena uses its own boss encounter without an unrelated mob roster")
	await floor_visit(&"B3")
	var croc:=find("crocodile")
	check(croc.health==620 and croc.visual.scale.x>1.5 and croc.visual.find_children("*Mask","Node3D",true,false).size()==1,"Crocodile Warden has a heavy budget and a distinct articulated crocodile silhouette")
	arrange(croc,Vector3(0,-47.94,-40),Vector3(0,-47.94,-38))
	await frames()
	croc.weapon_combat._begin(Moves.move("crocodile",&"special_y"))
	croc.weapon_combat.elapsed=.9
	croc.weapon_combat.strike(0)
	check(p.health<1000 and p.velocity.y>=3,"Crocodile's accepted grab strike deals shared damage and tosses the player")
	p.weapon_combat.reset()
	p.velocity=Vector3.ZERO
	p.combat.blocking=true
	p.weapon_combat._facing=Vector3.FORWARD
	p.target_lock.select(croc)
	p.weapon_combat.parry_remaining=.18
	croc.weapon_combat.cancel()
	croc.weapon_combat._begin(Moves.move("crocodile",&"special_y"))
	croc.weapon_combat.elapsed=.9
	croc.weapon_combat.strike(0)
	check(p.weapon_combat.last_parried and p.health==1000 and croc.weapon_combat.stagger_remaining>.99,"Heavy enemy attacks retain the existing zero-damage parry and one-second recoil")
	croc.reset_encounter()
	arrange(croc,Vector3(0,-47.94,-40),Vector3(0,-47.94,-38))
	croc.controls.active=true
	croc.controls.decision=0
	croc._awake=true
	croc.set_physics_process(true)
	croc.weapon_combat.set_physics_process(true)
	await frames(ceili(hz*2.5))
	check(croc.controls.decisions>0 and p.health<1000,"Crocodile AI commits and lands its own real timed attacks")
	freeze()
	await floor_visit(&"B4")
	var ibis:=find("ibis")
	arrange(ibis,Vector3(0,-63.94,-45),Vector3(0,-63.94,-35))
	await frames()
	ibis.weapon_combat._begin(Moves.move("ibis",&"attack_right"))
	ibis.weapon_combat.strike(0)
	check(ibis.weapon_combat.arrows.size()==3 and p.health==1000,"Ibis volley creates three visible moving glyphs without instant damage")
	await frames(ceili(hz*.9))
	check(p.health<1000,"Swept glyph projectiles deal real combat damage")
	p.weapon_combat.reset()
	ibis.weapon_combat._begin(Moves.move("ibis",&"special_x"))
	ibis.weapon_combat.strike(0)
	check(ibis.weapon_combat.fields.size()==1 and p.health==1000,"Glyph field shows a warning before its first active pulse")
	await frames(ceili(hz*.9))
	check(p.health<1000,"The visible glyph field becomes a real timed attack volume")
	encounter.ritual(ibis,"ward")
	encounter.ritual(ibis,"chant")
	check(ibis.ward_time>4 and ibis.support_time>4,"Scribe's ward and chant apply bounded defensive and ally support windows")
	ibis.reset_encounter()
	arrange(ibis,Vector3(0,-63.94,-45),Vector3(0,-63.94,-35))
	ibis.controls.active=true
	ibis.controls.decision=0
	ibis._awake=true
	ibis.set_physics_process(true)
	ibis.weapon_combat.set_physics_process(true)
	await frames(ceili(hz*2.0))
	check(ibis.controls.decisions>0 and p.health<1000,"Ibis AI observes the player and releases its own damaging glyph volley")
	freeze()
	await floor_visit(&"B5")
	var walker:=find("tomb_walker")
	check(walker.buried and not walker.visual.visible and walker.collision_layer==0,"Burial ambush waits dormant without hidden hurtboxes")
	p.global_position=walker.spawn+Vector3(0,0,2)
	walker._process(.02)
	check(not walker.buried and walker.visual.visible and walker.emergence>0,"Approaching a visible burial site raises its actual defender")
	var cursed:=find("cursed_warden")
	lethal(cursed)
	check(not cursed.dead and cursed.health==1 and cursed.reassemble_time>0,"Cursed Warden has one vulnerable reassembly window before its final defeat")
	lethal(cursed)
	check(cursed.dead,"A second hit can finish the reassembling Warden")
	await floor_visit(&"B6")
	check(encounter.champions_alive()==3 and find("renu").health!=find("sakhra").health,"Three named champions have separate roles and health budgets")
	encounter.encounter_clock=1
	var turns:=0
	for e in encounter.enemies:
		if e.traits.get("champion",false) and encounter.champion_turn(e): turns+=1
	check(turns==2,"Two champions pressure while the third rotates to a flank")
	var before: int=world.loot.pickups.size()
	lethal(find("renu"))
	lethal(find("tefet"))
	check(not encounter.defeated_ids.has("b6_trio_reward"),"Trio reward remains locked until all three fall")
	lethal(find("sakhra"))
	await frames(2)
	var sigil:=0
	for pickup in world.loot.pickups.values():
		if pickup.item_instance.item_type_id==&"sekhmet_sigil": sigil+=1
	check(sigil==1 and world.loot.pickups.size()==before+8 and encounter.defeated_ids.has("b6_trio_reward"),"Clearing all champions grants one reliable Sigil and their normal gear/glyph drops")
	await floor_visit(&"B7")
	var charmer:=find("charmer")
	var asp:=find("asp")
	var dead_id: String=asp.spawn_id
	lethal(asp)
	encounter.ritual(charmer,"summon")
	check(not encounter.defeated_ids.has(dead_id) and encounter.defeated_ids.has(charmer.spawn_id+"/summoned"),"Charmer can revive defeated serpents in one bounded wave")
	var count:=0
	for e in encounter.enemies:
		if is_instance_valid(e) and not e.dead and e.spawn_id==dead_id: count+=1
	check(count==1,"Summoning produces exactly one live replacement for a defeated snake")
	encounter.inflict_venom()
	var hp: float=p.health
	await frames(ceili(hz))
	check(p.health<hp and encounter._venom_time>0,"Venom applies bounded damage over time with a visible status")
	var snapshot:=Store.encode(p.inventory,world.loot.serialize_world(),[],"depths",String(travel.pyramid_id),travel.location_state())
	check(not snapshot.is_empty(),"Depth clears, summons and tiered drops fit the existing validated checkpoint")
	var content: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/pyramid_depth_equipment.json"))
	var copies:=true
	for item: Dictionary in content.items:
		var owned: Resource=Catalog.create(StringName(item.id))
		copies=copies and owned!=null and p.inventory.add_item(owned)
		var slot:=StringName("ring1" if item.family=="ring" else item.slot)
		copies=copies and world.loot.request_equip(p.inventory,slot,owned.instance_id)
		var preview:=Preview.model(item)
		root.add_child(preview)
		await process_frame
		preview.queue_free()
	check(copies and content.items.size()==22,"All 22 original loot copies equip and build their real catalog previews")
	check(Catalog.get_definition(&"venom_fang").max_stack==99,"Venom Fang is a normal stackable material")
	await floor_visit(&"B3")
	croc=find("crocodile")
	var preserved_id: String=croc.spawn_id
	croc.weapon_combat.health=123
	for id: StringName in [&"B4",&"B5",&"B7"]:
		p.global_position=travel.interior.floors[id].spawn_anchor.position
		await frames(2)
		freeze()
	check(encounter.spawned_floors.size()<=3 and encounter.dormant_states.has(preserved_id),"Distant full rigs unload into bounded primitive encounter snapshots")
	p.global_position=travel.interior.floors[&"B3"].spawn_anchor.position
	await frames(2)
	freeze()
	check(find("crocodile").health==123,"Returning to a streamed floor preserves surviving enemy health")
	var all_ids: Array=[]
	for id: StringName in travel.interior.floors:
		for entry: Array in encounter.roster_for(id): all_ids.append(entry[0])
	encounter.restore_defeats(all_ids)
	check(all_ids.size()>32 and not Store.encode(p.inventory,world.loot.serialize_world(),[],"depths",String(travel.pyramid_id),travel.location_state()).is_empty(),"A fully cleared expanded dungeon persists beyond the old 32-enemy checkpoint limit")
	p.respawn()
	freeze()
	check(encounter.defeated_ids.is_empty() and encounter._venom_time==0,"Death/fall recovery clears depth encounters, summon budgets and venom")
	world.queue_free()
	input.queue_free()
	await frames(2)
	print("PYRAMID DEPTHS ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
