extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Moves = preload("res://scripts/falcon_moves.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var encounter: Node3D
var controls: Intent
var checks:=0
var failures:=0
var hz:=60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)

func frames(count: int=2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func freeze_all() -> void:
	for enemy in encounter.enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.weapon_combat.set_physics_process(false)
		enemy.controls.active=false
		enemy.weapon_combat.cancel()

func enemy_named(id: String) -> CharacterBody3D:
	for enemy in encounter.enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.spawn_id==id: return enemy
	return null

func population(floor_id: StringName) -> int:
	var count:=0
	for enemy in encounter.enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.floor_id==floor_id: count+=1
	return count

func fresh() -> bool:
	var unique: Dictionary={}
	for enemy in encounter.enemies:
		if not is_instance_valid(enemy) or enemy.dead or unique.has(enemy.spawn_id): return false
		unique[enemy.spawn_id]=true
		if enemy.health!=enemy.weapon_combat.max_health or enemy.controls.aggro or enemy.global_position.distance_to(enemy.spawn)>.01: return false
	return encounter.defeated_ids.is_empty()

func targets() -> int:
	var count:=0
	for actor in get_nodes_in_group("combat_targets"):
		if actor.get("encounter")==encounter: count+=1
	return count

func place_glyph(id: StringName) -> bool:
	var item: Resource=Catalog.create(id)
	p.inventory.add_item(item)
	return world.loot.request_respawn_glyph(p.inventory,item.instance_id)

func kill(id: String) -> void:
	var enemy:=enemy_named(id)
	if enemy==null:
		check(false,"Fixture enemy is available: "+id)
		return
	enemy.receive_combat_hit(9999,enemy.combat_point()+Vector3.BACK,p,{"action":"attack_right","parryable":false,"hit_stun_level":0,"hit_stagger":0})

func die() -> void:
	p.combat.reset()
	p.dodge.cancel()
	p.receive_hit(9999,p.combat_point()+Vector3.BACK)

func run() -> void:
	create_timer(55).timeout.connect(func():push_error("DUNGEON RESPAWN WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	travel=world.dungeon_travel
	encounter=travel.encounters
	controls=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	world.loot.death_drop_probability=0
	p.global_position=Vector3(0,.05,8)
	await frames(10)
	check(place_glyph(&"home_respawn_glyph"),"Home glyph binds a safe overworld destination")
	travel._set_location(travel.pyramid_id)
	freeze_all()
	check(population(&"hub")==9 and not encounter.spawned_floors.has(&"B2"),"Entry populates only the hub")
	kill("skeleton_01")
	await frames(2)
	check(population(&"hub")==8 and encounter.defeated_ids.has("skeleton_01"),"A hub defeat clears that enemy for the current run")
	p.global_position=Vector3(0,-31.95,-40)
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	travel.interior.update_visibility(p.global_position,true)
	await frames(3)
	freeze_all()
	check(population(&"hub")==8 and population(&"B2")==8,"Changing floors keeps hub clears and creates the B2 roster")
	await frames(10)
	check(place_glyph(&"respawn_glyph"),"Personal glyph binds a reusable B2 destination")
	kill("b2_falcon_01")
	await frames(2)
	check(population(&"B2")==7 and encounter.defeated_ids.size()==2,"Hub and B2 defeats coexist within one run")
	var guardian:=enemy_named("jackal_01")
	guardian.weapon_combat.health=23
	guardian.controls.aggro=true
	guardian.global_position+=Vector3.RIGHT*2
	var archer:=enemy_named("b2_archer_01")
	archer.weapon_combat._begin(Moves.move("archer",&"special_x"))
	archer.weapon_combat.elapsed=.82
	archer.weapon_combat.strike(0)
	check(archer.weapon_combat.arrows.size()==1,"An actual enemy projectile is in flight before death")
	var drops: int=world.loot.pickups.size()
	die()
	check(world.respawn_glyphs.waiting and p.health==0 and not paused,"Lethal damage opens the live respawn choice")
	check(encounter.enemies.is_empty() and encounter.defeated_ids.is_empty() and targets()==0,"Death immediately retires both floor rosters and clears their defeat records")
	check(archer.weapon_combat.arrows.is_empty() and guardian.collision_layer==0,"Death cancels projectiles and old enemy collisions immediately")
	await frames(ceili(hz*.8))
	check(encounter.enemies.is_empty(),"No enemies repopulate while the dead player is choosing a destination")
	world.respawn_glyphs.choose("respawn")
	freeze_all()
	check(travel.inside() and p.global_position.y< -30 and p.health==1000,"Personal glyph reconstructs the player on B2")
	check(population(&"hub")==9 and population(&"B2")==8 and fresh(),"Death restores killed and surviving enemies at full health, at home, without hostility")
	check(targets()==17 and p.inventory.respawn_points.size()==2,"Fresh enemies are targetable exactly once and both glyphs remain reusable")
	await frames(ceili(hz*1.1))
	check(population(&"hub")==9 and population(&"B2")==8 and targets()==17,"Old dissolve callbacks cannot remove or duplicate rebuilt enemies")
	check(world.loot.pickups.size()==drops,"Resetting encounters preserves loot and grants no additional kill rewards")
	# A checkpoint saved inside is still a snapshot of that run, not an exit.
	kill("skeleton_02")
	kill("b2_falcon_02")
	await frames(2)
	var checkpoint: String="res://.godot/dungeon-enemy-respawn-"+str(hz)+".json"
	check(world.inventory_session.save_checkpoint(checkpoint,true),"Current-run clears and drops save through the real checkpoint service")
	p.respawn()
	freeze_all()
	check(population(&"B2")==0 and population(&"hub")==9 and fresh(),"Direct respawn also resets the run and leaves distant floors lazy")
	check(world.inventory_session.load_checkpoint(checkpoint),"An in-dungeon checkpoint reloads successfully")
	await frames(2)
	freeze_all()
	check(population(&"hub")==8 and population(&"B2")==7 and encounter.defeated_ids.size()==2,"Reloading inside restores exactly the checkpoint's run progress")
	drops=world.loot.pickups.size()
	die()
	world.respawn_glyphs.choose("home")
	check(not travel.inside() and p.health==1000 and encounter.enemies.is_empty() and encounter.defeated_ids.is_empty(),"Choosing Home after dungeon death leaves a fresh, dormant instance")
	check(not travel.location_state().has("enemy_defeats") and world.loot.pickups.size()==drops,"Outdoor saves omit cleared enemies while retaining dungeon loot")
	# Old versions persisted enemy clears even outside. They must not poison a new run.
	var legacy: Dictionary=Store.encode(p.inventory,world.loot.serialize_world(),[],world.loot.session_id,"overworld",{"enemy_defeats":["skeleton_01","b2_falcon_01"]})
	check(Store.store(checkpoint,legacy)==OK and world.inventory_session.load_checkpoint(checkpoint),"Legacy outdoor checkpoint with stale clears remains loadable")
	check(encounter.defeated_ids.is_empty() and encounter.enemies.is_empty(),"Loading outside discards legacy dungeon defeat records")
	travel._set_location(travel.pyramid_id)
	freeze_all()
	encounter.ensure_spawned(&"B2")
	freeze_all()
	check(population(&"hub")==9 and population(&"B2")==8 and fresh(),"Re-entry after a Home respawn starts with every enemy available")
	# Exit during the dissolve/deferred-reward window, followed by immediate re-entry.
	for cycle in range(2):
		kill("skeleton_01")
		travel._set_location(travel.OUTSIDE)
		check(not encounter.spawned and encounter.spawned_floors.is_empty() and targets()==0,"Exit clears all enemy state immediately, cycle "+str(cycle+1))
		travel._set_location(travel.pyramid_id)
		freeze_all()
		encounter.ensure_spawned(&"B2")
		freeze_all()
		check(fresh() and population(&"hub")==9 and population(&"B2")==8,"Re-entry repopulates one full roster, cycle "+str(cycle+1))
		await frames(2)
		check(targets()==17 and world.loot.pickups.size()==drops+3*(cycle+1),"Only the actual kill grants rewards; resets add no ghost targets or loot, cycle "+str(cycle+1))
	# No anchors retains the established immediate default respawn behavior.
	p.inventory.respawn_points.clear()
	p.inventory.changed.emit()
	kill("skeleton_01")
	die()
	freeze_all()
	check(not world.respawn_glyphs.waiting and p.health==1000 and population(&"hub")==9 and fresh(),"Death without glyphs immediately restores the default spawn and full encounter")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("DUNGEON ENEMY RESPAWN ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
