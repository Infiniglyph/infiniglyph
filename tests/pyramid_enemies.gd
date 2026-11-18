extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Floor = preload("res://scripts/pyramid_floor.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var encounter: Node3D
var checks := 0
var failures := 0
var hz := 60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func freeze(enemy: CharacterBody3D) -> void:
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.weapon_combat.set_physics_process(false)
	enemy.controls.active=false
	enemy.weapon_combat.cancel()

func shot(label: String, point: Vector3, offset: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.global_position=point+offset
	camera.look_at(point+Vector3.UP*1.1)
	camera.current=true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("TEST WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.neon_glow_enabled=false
	root.add_child(world)
	p=world.player
	var controls:=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	travel=world.dungeon_travel
	encounter=travel.encounters
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(6)
	check(not encounter.spawned and encounter.enemies.is_empty(),"Dungeon roster is lazy and does not populate the overworld")
	var was_target:=p.is_in_group("combat_targets")
	var was_layer:=p.get_collision_layer_value(2)
	travel._set_location(travel.pyramid_id)
	await frames(8)
	check(encounter.enemies.size()==9 and p.is_in_group("combat_targets") and p.get_collision_layer_value(2),"Entry instance registers six skeletons and three jackal guardians with player hurtboxes")
	var same_world:=true
	var spawn_ok:=true
	var guardian: CharacterBody3D
	var skeleton: CharacterBody3D
	var elite: CharacterBody3D
	for enemy in encounter.enemies:
		same_world=same_world and enemy.get_world_3d()==p.get_world_3d() and enemy.get_world_3d()!=travel.outside_root.get_world_3d()
		var cell: Vector2i=encounter.nearest_cell(enemy.spawn)
		spawn_ok=spawn_ok and Floor.hub_open(cell.x,cell.y) and enemy.spawn.distance_to(p.global_position)>20
		if enemy.enemy_kind=="jackal": guardian=enemy
		else: skeleton=enemy
		if enemy.elite: elite=enemy
		freeze(enemy)
	check(same_world and spawn_ok,"All enemy spawns occupy walkable maze cells, away from the safe arrival door and in their own World3D")
	check(guardian.weapon_combat.rig.models.has(&"warden_khopesh") and skeleton.weapon_combat.rig.models.has(&"tomb_blade"),"Enemies wield real equipped khopesh and tomb blades through the shared rig")
	check(elite.health>guardian.health or elite==guardian,"Exalted guardian has a larger difficulty budget")
	var waypoint: Vector3=encounter.next_waypoint(Vector3(-16,0,-24),Vector3(16,0,-24))
	check(waypoint!=Vector3(16,0,-24) and waypoint.distance_to(Vector3(-16,0,-24))<=8.1,"Maze pursuit routes around walls through adjacent walkable cells")
	guardian=encounter.enemies[2]
	guardian.global_position=Vector3(0,.05,-25.5)
	p.global_position=Vector3(0,.05,-24)
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	guardian.controls.active=true
	guardian.controls.decision=0
	guardian._awake=true
	guardian.set_process(true)
	guardian.set_physics_process(true)
	guardian.weapon_combat.set_physics_process(true)
	var before: float=p.health
	await frames(ceili(hz*2.5))
	check(guardian.controls.decisions>0 and p.health<before,"Guardian detects a visible intruder and lands attacks through the shared combat controller")
	freeze(guardian)
	guardian.reset_encounter()
	check(not guardian.controls.aggro and guardian.health==guardian.weapon_combat.max_health and guardian.global_position.distance_to(guardian.spawn)<.05,"Encounter reset clears aggression and restores surviving enemies home")
	guardian.target_lock.select(p)
	guardian.combat.blocking=true
	guardian.weapon_combat.parry_remaining=0
	var guarded: float=guardian.receive_combat_hit(20,p.combat_point(),p,{"action":"attack_right","parryable":true,"hit_stun_level":0,"hit_stagger":0})
	check(guardian.weapon_combat.last_blocked and guarded<5,"Jackal shield uses normal weapon-specific block power")
	guardian.weapon_combat.parry_remaining=.18
	var guard_health: float=guardian.health
	guardian.receive_combat_hit(20,p.combat_point(),p,{"action":"attack_right","parryable":true,"hit_stun_level":0,"hit_stagger":0})
	check(guardian.health==guard_health and guardian.weapon_combat.last_parried and p.weapon_combat.stagger_remaining>.99,"Jackal defense uses shared zero-damage parry and one-second attacker stun")
	p.weapon_combat.reset()
	guardian.combat.blocking=false
	guardian.reset_encounter()
	# Review original procedural designs at rest without changing combat state.
	guardian.visual.rotation.y=0
	await shot("pyramid_jackal_guardian",guardian.global_position,Vector3(2.2,1.9,3.8))
	skeleton.visual.rotation.y=0
	await shot("pyramid_restless_skeleton",skeleton.global_position,Vector3(1.7,1.8,3.2))
	# A genuine lethal shared hit resolves once, produces gear and a tiered glyph.
	skeleton.global_position=Vector3(8,.05,-24)
	var death_point: Vector3=skeleton.global_position
	var dead_id: String=skeleton.spawn_id
	var original_count: int=world.loot.pickups.size()
	var damage: float=skeleton.receive_combat_hit(9999,p.combat_point(),p,{"action":"attack_right","parryable":true,"hit_stun_level":0,"hit_stagger":0,"attack_serial":321})
	check(damage>0 and skeleton.dead and not skeleton.is_in_group("combat_targets") and skeleton.collision_layer==0,"Defeated monsters immediately stop fighting and lose their hurtboxes")
	skeleton.on_combat_defeat()
	await frames(3)
	check(world.loot.pickups.size()==original_count+3 and encounter.defeated_ids.has(dead_id),"One death produces one common glyph, one gear copy and bone shards, without duplicate rewards")
	await shot("pyramid_monster_dissolving",death_point,Vector3(2,1.7,3.3))
	await frames(ceili(hz*.8))
	check(not is_instance_valid(skeleton),"Monster body dissolves away instead of leaving a corpse")
	var drops:=0
	var glyph: Node3D
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.global_position.distance_to(death_point)<4:
			drops+=1
			check(pickup.location_id==travel.pyramid_id and pickup.get_world_3d()==p.get_world_3d(),"Dungeon reward remains in the correct instance")
			if pickup.item_instance.item_type_id==&"monster_glyph_common": glyph=pickup
	check(drops==3 and is_instance_valid(glyph) and is_instance_valid(glyph.get_node_or_null("RemnantGlyph")),"A persistent collectible glyph remains visibly beside the equipment")
	await shot("pyramid_monster_rewards",death_point,Vector3(1.6,1.4,2.6))
	var common: Resource=Catalog.get_definition(&"monster_glyph_common")
	var uncommon: Resource=Catalog.get_definition(&"monster_glyph_uncommon")
	var rare: Resource=Catalog.get_definition(&"monster_glyph_rare")
	check(common.custom_properties.glyph_scale<uncommon.custom_properties.glyph_scale and uncommon.custom_properties.glyph_scale<rare.custom_properties.glyph_scale and encounter.glyph_for(3)==&"monster_glyph_rare","Enemy difficulty determines progressively larger and rarer remnant glyphs")
	var state: Dictionary=travel.location_state()
	var saved: Dictionary=Store.encode(p.inventory,world.loot.serialize_world(),[],"pyramid_enemy_test",String(travel.pyramid_id),state)
	check(not saved.is_empty() and saved.location_state.enemy_defeats.has(dead_id),"Checkpoint retains cleared enemies alongside dungeon drops")
	var corrupt: Dictionary=saved.duplicate(true)
	corrupt.location_state.enemy_defeats=[dead_id,dead_id]
	check(Store.decode(corrupt).is_empty(),"Checkpoint validation rejects duplicate defeat records")
	# Saveable collectible ownership, using the existing authority.
	p.global_position=glyph.global_position+Vector3(0,.03,.7)
	p.velocity=Vector3.ZERO
	await frames(2)
	var glyph_id: String=glyph.item_instance.instance_id
	check(world.loot.request_pickup(p.inventory,glyph) and p.inventory.get_item(glyph_id)!=null,"Remnant glyph can be picked up into normal inventory ownership")
	var inv_saved: Dictionary=Store.encode(p.inventory)
	check(not inv_saved.is_empty(),"Collected glyph survives normal checkpoint serialization")
	guardian.controls.aggro=true
	p.respawn()
	var fresh: bool=encounter.enemies.size()==9 and encounter.defeated_ids.is_empty()
	for enemy in encounter.enemies:
		fresh=fresh and not enemy.controls.aggro and enemy.health==enemy.weapon_combat.max_health and enemy.global_position.distance_to(enemy.spawn)<.05
	check(fresh,"Player respawn restores the full roster at home with full health and no hostility")
	encounter.restore_defeats([])
	await frames(2)
	check(encounter.enemies.size()==9,"An older checkpoint can restore monsters defeated since it was saved")
	encounter.restore_defeats(state.enemy_defeats)
	await frames(2)
	check(encounter.enemies.size()==8 and encounter.defeated_ids.has(dead_id),"Loading a cleared checkpoint restores exactly its surviving roster")
	travel._set_location(travel.OUTSIDE)
	check(not encounter.active and p.is_in_group("combat_targets")==was_target and p.get_collision_layer_value(2)==was_layer,"Leaving restores the player's original overworld target membership")
	check(encounter.enemies.is_empty() and encounter.defeated_ids.is_empty() and not travel.location_state().has("enemy_defeats"),"Leaving clears the run and removes defeated records from outdoor checkpoints")
	travel._set_location(travel.pyramid_id)
	check(encounter.enemies.size()==9 and encounter.defeated_ids.is_empty(),"Re-entry restores the full roster without duplicate spawns")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("PYRAMID ENEMIES ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
