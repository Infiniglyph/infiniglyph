extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Moves = preload("res://scripts/falcon_moves.gd")
const Store = preload("res://scripts/inventory_store.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var encounter: Node3D
var checks:=0
var failures:=0
var hz:=60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")
func frames(count: int=2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func freeze(actor: CharacterBody3D) -> void:
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.controls.active=false
	actor.weapon_combat.cancel()
func arrange(actor: CharacterBody3D, point: Vector3, player_point: Vector3) -> void:
	actor.reset_encounter()
	actor.global_position=point
	actor.velocity=Vector3.ZERO
	actor.fall_damage.reset()
	p.global_position=player_point
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.combat.reset()
	p.weapon_combat.reset()
	actor.target_lock.select(p)
	p.target_lock.select(actor)
func shoot(archer: CharacterBody3D) -> void:
	archer.weapon_combat.cancel()
	archer.weapon_combat._begin(Moves.move("archer",&"special_x"))
	archer.weapon_combat.elapsed=.82
	archer.weapon_combat.strike(0)

func run() -> void:
	create_timer(55).timeout.connect(func():push_error("B2 WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	var controls:=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	world.loot.death_drop_probability=0
	travel=world.dungeon_travel
	encounter=travel.encounters
	await frames(4)
	check(encounter.enemies.is_empty(),"No B2 actors are created in the overworld")
	travel._set_location(travel.pyramid_id)
	await frames(4)
	check(encounter.enemies.size()==9 and not encounter.spawned_floors.has(&"B2"),"Entry hub retains its roster; B2 stays lazy until visited")
	p.global_position=Vector3(0,-31.95,-40)
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	travel.interior.update_visibility(p.global_position,true)
	await frames(5)
	check(encounter.enemies.size()==17 and encounter.spawned_floors.has(&"B2"),"First B2 visit creates three Sentinels, three Winged Skeletons and two Archers")
	var falcon: CharacterBody3D
	var archer: CharacterBody3D
	var elite: CharacterBody3D
	var winged: CharacterBody3D
	var safe:=true
	for enemy in encounter.enemies:
		freeze(enemy)
		if enemy.floor_id!=&"B2": continue
		var query:=PhysicsShapeQueryParameters3D.new()
		var capsule:=CapsuleShape3D.new()
		capsule.radius=.28
		capsule.height=1.85
		query.shape=capsule
		query.transform.origin=enemy.spawn+Vector3.UP*.95
		query.collision_mask=1
		safe=safe and enemy.get_world_3d()==p.get_world_3d() and p.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
		if enemy.enemy_kind=="falcon": falcon=enemy
		if enemy.enemy_kind=="archer": archer=enemy
		if enemy.enemy_kind=="winged_skeleton": winged=enemy
		if enemy.elite: elite=enemy
	check(safe,"All B2 spawns have real capsule clearance and belong to the dungeon World3D")
	check(falcon.weapon_combat.rig.models.has(&"horuswing_blades") and falcon.visual.wings.roots.size()==2,"Sentinel wields equipped curved blades and articulated feather wings")
	check(falcon.visual.wings.find_children("*","MeshInstance3D",true,false).size()==6 and falcon.visual.wings.roots[0].basis.determinant()>0,"Both mirrored wings use six cached surfaces and stable positive-scale animation roots")
	check(winged.visual.wings.bones and archer.weapon_combat.rig.models[&"tomb_blade"].right.get_child_count()>0,"Supporting skeletons have bone wings and an enemy-only physical bow")
	check(not Catalog.get_definition(&"bow") and Catalog.get_definition(&"horuswing_blades")!=null,"Enemy bow does not reintroduce a retired player weapon class")
	check(encounter.next_waypoint(Vector3(20,-32,-40),Vector3(-20,-32,0),&"B2")==Vector3(0,-32,-40),"Two-court pursuit first approaches the real central portal instead of cutting a wall")
	# Actual controller flight, not animated hovering or a teleported body.
	arrange(falcon,Vector3(0,-31.95,-43),Vector3(0,-31.95,-40))
	p.set_physics_process(false)
	falcon.controls.active=true
	falcon.controls.decision=4
	falcon.set_physics_process(true)
	falcon.weapon_combat.set_physics_process(true)
	var peak:=falcon.global_position.y
	var displacement:=0.0
	var previous:=falcon.global_position
	for i in range(ceili(hz*1.4)):
		await frames(1)
		peak=maxf(peak,falcon.global_position.y)
		displacement=maxf(displacement,falcon.global_position.distance_to(previous))
		previous=falcon.global_position
	check(falcon.controls.sky_steps>0 and peak>falcon.floor_y+2,"Aerial approach uses real jump and Sky Jump impulses with visible air steps")
	check(displacement<25.0/hz+.18,"Aerial pursuit moves continuously through the player's physics controller")
	p.global_position.y=-25
	for i in range(ceili(hz*2.5)):
		await frames(1)
		peak=maxf(peak,falcon.global_position.y)
	check(peak>falcon.floor_y+6 and falcon.controls.sky_steps>1,"Sentinel follows a visibly airborne target with additional Sky Jumps")
	if peak<=falcon.floor_y+6: print("CHASE: peak=",peak," current=",falcon.global_position," velocity=",falcon.velocity," steps=",falcon.controls.sky_steps)
	freeze(falcon)
	arrange(falcon,Vector3(0,-25.8,-43),Vector3(0,-31.95,-40))
	falcon.set_physics_process(true)
	falcon.weapon_combat.set_physics_process(true)
	falcon.weapon_combat._on_action(&"special_y",&"down")
	var before: float=p.health
	check(falcon.weapon_combat.active_move.dive and falcon.weapon_combat.active_move.hits[0]>.7,"Dive has a readable windup before its shared melee contact window")
	await frames(ceili(hz*1.3))
	check(p.health<before and falcon.global_position.y>=-32.08,"Diving strike deals real damage and lands against the physical floor")
	freeze(falcon)
	arrange(falcon,Vector3(0,-26.5,-42),Vector3(0,-29,-40))
	falcon.controls.active=true
	falcon.controls.decision=0
	falcon.controls.decisions=0
	falcon.controls.sample()
	var request: Array=falcon.controls.consume_combat_requests()
	check(not request.is_empty() and request[0].value==&"special_y","Observed airborne escape can trigger the telegraphed dive decision")
	falcon.controls.active=false
	for action: StringName in [&"attack_left",&"special_x"]:
		arrange(falcon,Vector3(0,-28,-42),Vector3(0,-28,-40))
		await frames(2) # Flush both relocated hurtboxes into the physics space.
		falcon.weapon_combat._begin(Moves.move("falcon",action))
		var hits: Array=falcon.weapon_combat.active_move.hits.duplicate()
		for pulse in range(hits.size()):
			falcon.weapon_combat.elapsed=float(hits[pulse])
			falcon.weapon_combat.strike(pulse)
		check(p.health<1000,"Aerial technique uses actual shared contact volumes: "+String(falcon.weapon_combat.active_move.get("name",action)))
	# An arrow travels through the same damage, block and parry resolver.
	arrange(archer,Vector3(25,-31.95,2),Vector3(25,-31.95,12))
	await frames(2)
	archer.controls.active=true
	archer.controls.decision=0
	archer.set_physics_process(true)
	archer.weapon_combat.set_physics_process(true)
	await frames(ceili(hz*1.8))
	check(archer.controls.decisions>0 and p.health<1000,"Skeletal Archer AI visibly draws and lands a real projectile through combat input")
	freeze(archer)
	arrange(archer,Vector3(0,-31.95,-50),Vector3(0,-31.95,-40))
	shoot(archer)
	check(archer.weapon_combat.arrows.size()==1 and is_equal_approx(p.health,1000),"Archer releases a visible moving arrow without instant damage")
	await frames(ceili(hz*.9))
	check(p.health<1000 and archer.weapon_combat.arrows.is_empty(),"Swept arrow flight damages an exposed player once and is reclaimed")
	arrange(archer,Vector3(0,-31.95,-45),Vector3(0,-31.95,-40))
	p.combat.blocking=true
	p.weapon_combat.parry_remaining=0
	shoot(archer)
	await frames(ceili(hz*.5))
	check(p.weapon_combat.last_blocked and p.health>995,"Normal weapon guard mitigates a physical skeletal arrow")
	arrange(archer,Vector3(0,-31.95,-45),Vector3(0,-31.95,-40))
	p.combat.blocking=true
	shoot(archer)
	await frames(ceili(hz*.16))
	p.weapon_combat.parry_remaining=.18
	await frames(ceili(hz*.25))
	check(p.health==1000 and p.weapon_combat.last_parried and archer.weapon_combat.stagger_remaining>.99,"Parrying an arrow negates damage and gives the archer the shared one-second stun")
	arrange(archer,Vector3(0,-31.95,-45),Vector3(0,-31.95,-40))
	p.dodge.start(Vector3.RIGHT)
	p.dodge.elapsed=p.dodge.DURATION*.5
	shoot(archer)
	await frames(ceili(hz*.5))
	check(p.health==1000 and p.weapon_combat.last_evaded,"Existing dodge invulnerability also defeats incoming arrows")
	p.dodge.cancel()
	var wall:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(4,4,.3)
	shape.shape=box
	wall.add_child(shape)
	travel.interior.add_child(wall)
	wall.position=Vector3(0,-30,-42.5)
	await frames(2)
	arrange(archer,Vector3(0,-31.95,-45),Vector3(0,-31.95,-40))
	shoot(archer)
	await frames(ceili(hz*.5))
	check(p.health==1000 and archer.weapon_combat.arrows.is_empty(),"An opaque wall physically stops arrows and their damage")
	wall.queue_free()
	await frames(2)
	# Wearable loot shares the NPC's actual geometry, including closed feet.
	for pair: Array in [[&"horuswing_blades",&"up"],[&"sentinel_spear",&"left"],[&"falcon_sentinel_mantle",&"body"],[&"skyguard_tassets",&"legs"],[&"eye_of_horus_seal",&"ring1"]]:
		var item: Resource=Catalog.create(pair[0])
		check(item!=null and p.inventory.add_item(item) and world.loot.request_equip(p.inventory,pair[1],item.instance_id),"B2 loot equips through normal owned slots: "+String(pair[0]))
	check(not p.visual.foot_meshes.LeftLeg.visible and not p.visual.foot_meshes.RightLeg.visible,"Skyguard greaves fully cover the original bright feet")
	check(not Store.encode(p.inventory).is_empty(),"All five B2 equipment copies persist through the normal checkpoint format")
	arrange(elite,Vector3(0,-26,-45),Vector3(0,-31.95,-40))
	var dead_id: String=elite.spawn_id
	var count: int=world.loot.pickups.size()
	elite.receive_combat_hit(9999,p.combat_point(),p,{"action":"attack_right","attack_serial":999})
	elite.on_combat_defeat()
	await frames(3)
	check(elite.dead and elite.collision_layer==0 and world.loot.pickups.size()==count+2,"Airborne elite defeat dissolves once and produces gear plus a Rare glyph")
	var grounded:=true
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.location_id==travel.pyramid_id: grounded=grounded and absf(pickup.global_position.y+32)<.15
	check(grounded,"Airborne rewards are placed on supported B2 ground in their original instance")
	var state: Dictionary=travel.location_state()
	check(state.enemy_defeats.has(dead_id) and not Store.encode(p.inventory,world.loot.serialize_world(),[],"b2_test",String(travel.pyramid_id),state).is_empty(),"B2 defeat records and drops save alongside the existing hub records")
	encounter.restore_defeats([])
	await frames(2)
	check(encounter.enemies.size()==17,"Loading an older state rebuilds both visited floor rosters")
	encounter.restore_defeats([dead_id])
	await frames(2)
	check(encounter.enemies.size()==16 and encounter.defeated_ids.has(dead_id),"Restoring a cleared state keeps the defeated B2 Sentinel removed")
	var b2: CharacterBody3D
	for enemy in encounter.enemies:
		if enemy.floor_id==&"B2": b2=enemy
	p.global_position=Vector3(0,.05,-8)
	await frames(3)
	check(not b2.is_physics_processing() and b2.weapon_combat.active_move.is_empty(),"Leaving B2 for another storey suspends its attacks and AI")
	travel._set_location(travel.OUTSIDE)
	check(not encounter.active and encounter.defeated_ids.is_empty() and encounter.enemies.is_empty() and not travel.location_state().has("enemy_defeats"),"Exiting resets B2 clears and retires its actors without cross-world combat")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("PYRAMID B2 ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
