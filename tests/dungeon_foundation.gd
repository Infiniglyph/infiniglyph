extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Interior = preload("res://scripts/pyramid_interior.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Session = preload("res://scripts/inventory_session.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var controls: Intent
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func transport_node_count() -> int:
	var count:=world.find_children("*","",true,false).size()
	# Autonomous purchases legitimately create persistent private goods stores
	# while the player travels. They are separate from environment/portal leaks.
	for store: Node in world.civilian_services.economy.npc_stores.values(): count-=1+store.find_children("*","",true,false).size()
	return count

func place(point: Vector3) -> void:
	p.global_position=point
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(12)

func finish_transition() -> void:
	for i in range(hz*4):
		if not travel.busy: break
		if i==0: check(p.visible and p.visual.is_visible_in_tree() and p.transition_locked,"Character stays visible and safely pinned during environmental assembly")
		await frames(1)
	check(not travel.busy and not p.transition_locked and controls.gameplay_enabled,"Transition completes and restores normal input")
	await frames(4)

func key_g() -> void:
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_G
	key.pressed=true
	controls._unhandled_input(key)
	await frames(2)

func shot(label: String, offset: Vector3 = Vector3(2.5,2.5,3.0)) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	if label=="deconstruction": await frames(ceili(hz*.3))
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.global_position=p.global_position+offset
	camera.look_at(p.global_position+Vector3.UP*1.1)
	camera.current=true
	await frames(1)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/dungeon_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func enter() -> void:
	await place(world.wider_world.pyramid.to_global(Vector3(65.5,.15,0)))
	await frames(ceili(.6*hz))
	await key_g()
	check(travel.busy,"Fresh doorway G activation starts entry")
	await finish_transition()
	check(travel.inside(),"Entry cycle reaches the interior")

func leave() -> void:
	await place(Vector3(0,.05,1.5))
	await frames(ceili(.6*hz))
	# Real sample() polls neutral trigger axes after input capture ends.
	controls.set_right_trigger(0)
	controls.set_right_trigger(1)
	await frames(1)
	check(not travel.busy,"Bare RT waits for release rather than breaking RT combat combinations")
	controls.set_right_trigger(0)
	await frames(2)
	check(travel.busy,"Fresh RT tap starts doorway exit")
	await finish_transition()
	check(not travel.inside(),"Exit cycle reaches the outdoors")

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.dungeon_enemies_enabled=false
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	travel=world.dungeon_travel
	controls=Intent.new()
	root.add_child(controls)
	controls.interaction_context=world.inventory_session
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(10)
	check(travel.ready_for_travel and travel.contexts.size()==6 and travel.room_contents.is_empty() and not is_instance_valid(travel.hall_content) and not travel.inside(),"Prepared dungeon, original outdoors, three dormant rentals and shop identity stay separate")
	check(travel.interior.get_world_3d()!=travel.outside_root.get_world_3d() and p.get_world_3d()==travel.outside_root.get_world_3d(),"Interior owns an independent World3D; outdoor player and architecture still share their original world")
	check(travel.home_anchor.name==&"TemporaryHomeSpawn" and travel.home_anchor.global_position==p.spawn,"Open-world respawn uses a clearly identified temporary home, ready for a future property anchor")
	check(p.weapon_combat.feedback==world.sparring_partner.weapon_combat.feedback,"Outdoor actors retain the player's shared combat impact pool after scenery separation")
	var ids: Array[StringName]=[&"eturnull_manuscript",&"eturnull_hat",&"kyren_scarf"]
	for i in range(ids.size()):
		var item: Resource=Catalog.create(ids[i])
		p.inventory.add_item(item)
		check(world.loot.request_equip(p.inventory,[&"down",&"head",&"body"][i],item.instance_id),"Equip continuity reference "+String(ids[i]))
	p.combat.selected_slot=&"down"
	p.combat.sheathed=false
	p.weapon_combat.sync_rig()
	var character_id:=p.get_instance_id()
	var visual_id: int=p.visual.get_instance_id()
	var owned: Dictionary=p.inventory.serialize()
	p.weapon_combat.health=740
	await place(world.wider_world.pyramid.to_global(Vector3(65.5,.15,0)))
	check(travel.focused_door()!=null and world.inventory_session.can_talk(),"Existing pyramid vestibule offers the focused G / RT interaction")
	controls.set_right_trigger(0)
	controls.set_right_trigger(1)
	var special:=InputEventJoypadButton.new()
	special.button_index=JOY_BUTTON_Y
	special.pressed=true
	controls._unhandled_input(special)
	var requests: Array=controls.consume_combat_requests()
	special.pressed=false
	controls._unhandled_input(special)
	controls.consume_combat_requests()
	controls.set_right_trigger(0)
	check(not controls.consume_interaction() and requests.size()==1 and requests[0].value==&"special_rt_y","RT plus Y retains its weapon-art command without also activating the focused doorway")
	await frames(hz/2)
	check(not travel.busy and not travel.inside(),"Walking near the doorway alone never enters the dungeon")
	await key_g()
	check(travel.busy and not controls.gameplay_enabled and p.transition_locked,"G starts exactly one environmental transition and gates movement/combat")
	check(not travel.interact(),"Repeated activation cannot start overlapping transitions")
	check(travel._effect.effects.size()<travel._effect.pieces.size(),"Environment meshes share palette materials and bounded uniform updates during manifestation")
	check(p.receive_hit(100,Vector3.ZERO)==0 and p.weapon_combat.receive_environment_damage(100)==0 and p.health==740,"Transition protects the pinned character against weapon and environmental damage")
	world.start_menu.open_menu()
	check(not world.start_menu.is_open,"System menu cannot release the brief transition input lock")
	await shot("deconstruction")
	await finish_transition()
	check(travel.inside() and p.get_world_3d()==travel.interior.get_world_3d() and p.is_on_floor(),"Player enters the fully prepared independent interior and lands on its real floor")
	check(p.get_instance_id()==character_id and p.visual.get_instance_id()==visual_id and p.inventory.serialize()==owned and p.health==740,"The same player, visual, equipment, cosmetics and health survive entry")
	check(not travel.outside_root.visible and travel.outside_root.process_mode==Node.PROCESS_MODE_DISABLED,"Inactive exterior cannot attack or render across the instance boundary")
	check(travel._effect.pieces.is_empty() and not travel.focused_door(),"Temporary manifestation materials are restored and arrival does not immediately re-exit")
	var reachable: Dictionary={Vector2i(4,0):true}
	var queue: Array[Vector2i]=[Vector2i(4,0)]
	var branches:=0
	while not queue.is_empty():
		var cell: Vector2i=queue.pop_front()
		var degree:=0
		for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:=cell+step
			if not Interior.open_at(next.x,next.y): continue
			degree+=1
			if not reachable.has(next):
				reachable[next]=true
				queue.append(next)
		if degree>=3: branches+=1
	check(reachable.size()==travel.interior.open_cells.size() and branches>=3,"The modest fixed labyrinth has connected branching passages, turns and dead ends")
	check(travel.interior.glyph_count>100 and travel.interior.chunks.size()==4,"Recognizable glyph bands and architecture share four static batches rather than thousands of glyph nodes")
	var inside_space:=p.get_world_3d().direct_space_state
	var floor:=inside_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,-8),Vector3(0,-2,-8),1))
	var wall:=inside_space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,-8),Vector3(0,2,-24),1))
	check(not floor.is_empty() and absf(floor.position.y)<.01 and not wall.is_empty(),"Maze floors, walls and turns have matching physical support and obstruction")
	check(not p.target_lock.living(world.sparring_partner),"Combat targeting rejects an actor from the other World3D")
	await shot("interior")
	# Exercise the known clear corridor, independently of the doorway-relative
	# heading under test above. The old compass heading ran straight into a wall.
	world.camera_rig.yaw=0
	world.camera_rig.reset_follow()
	controls.move=Vector2.UP
	controls.boost=true
	await frames(hz/2)
	check(p.velocity.length()>4,"The existing sprint/momentum controller works inside the labyrinth")
	controls.move=Vector2.ZERO
	controls.boost=false
	controls.jump_requested=true
	await frames(5)
	controls.jump_requested=true
	await frames(2)
	check(p.air_step_count>0,"Sky Jump uses the same unlimited movement system inside")
	check(p.dodge.start(Vector3.RIGHT),"Directional phase dodge remains available inside")
	p.dodge.cancel()
	world.loot.death_drop_probability=1
	for point: Vector3 in [Vector3(0,.05,-8),Vector3(16,.05,-8)]:
		await place(point)
		p.weapon_combat.receive_environment_damage(10000)
		await frames(4)
		check(travel.inside() and p.health==1000 and p.global_position.distance_to(travel.interior.spawn_anchor.global_position)<.15,"Dungeon death retains the instance and respawns at its front door")
	var losses: Array=world.loot.markers.for_owner(p.inventory.owner_id)
	check(losses.size()==2 and world.loot.pickups[losses[0].pickup_id].get_world_3d()==travel.interior.get_world_3d(),"Two dungeon deaths retain both independently recoverable drops in the interior world")
	world.inventory_session._refresh_losses()
	check(world.inventory_session.loss_hint.text.contains("X 16") and world.inventory_session.loss_hint.text.contains("2 unclaimed"),"Recovery guidance follows the most recent outstanding loss even when an older one is nearer")
	var checkpoint: String="user://tests/dungeon_foundation.json"
	check(world.inventory_session.save_checkpoint(checkpoint,true),"Checkpoint preserves ownership and all outstanding dungeon drops")
	var saved: Dictionary=Store.load_snapshot(checkpoint)
	check(saved.get("location_context")==String(travel.pyramid_id) and saved.world_drops.any(func(row: Dictionary): return row.get("location_id")==String(travel.pyramid_id)),"Version-one checkpoint retains explicit player and drop location identities")
	var pickup_ids: Array=world.loot.pickups.keys()
	await leave()
	check(not travel.inside() and p.get_world_3d()==travel.outside_root.get_world_3d() and p.global_position.distance_to(world.wider_world.pyramid.arrival_anchor.global_position)<.2,"RT exit reconstructs the existing outdoors and places the same player safely at the pyramid")
	check(world.loot.pickups.keys()==pickup_ids and world.inventory_session.loss_hint.text.contains("PYRAMID"),"Leaving keeps dungeon drops intact and recovery guidance names their other location")
	check(not world.loot.request_pickup(p.inventory,world.loot.pickups[losses[-1].pickup_id]),"An outdoor player cannot collect a drop in a different world")
	world.loot.death_drop_probability=0
	await place(Vector3(0,.05,25))
	p.weapon_combat.receive_environment_damage(10000)
	check(not travel.inside() and p.global_position==travel.home_anchor.global_position and p.health==1000,"Open-world death restores health at home rather than the pyramid doorway")
	var foreign_save: Dictionary=saved.duplicate(true)
	foreign_save.world_drops[-1].location_id="pyramid/other-owner"
	var before_invalid: Dictionary=p.inventory.serialize()
	check(Store.store(checkpoint+".foreign",foreign_save)==OK and not world.inventory_session.load_checkpoint(checkpoint+".foreign") and p.inventory.serialize()==before_invalid and world.loot.pickups.keys()==pickup_ids and not travel.inside(),"Unknown instance drops fail checkpoint loading without changing inventory, drops or location")
	# Validate every persisted drop against its own world before the atomic load.
	for row: Dictionary in saved.world_drops:
		var point:=Vector3(row.position[0],row.position[1],row.position[2])
		var location:=StringName(row.get("location_id","overworld"))
		var saved_floor: Dictionary=world.loot.supported_position(point,location)
		check(not saved_floor.is_empty() and absf(saved_floor.point.y-point.y)<.4 and world.loot.clear_volume(point,location),"Saved drop support remains queryable in its dormant location")
	check(world.inventory_session.load_checkpoint(checkpoint),"An interior checkpoint reloads its location and both drop identities atomically")
	await frames(4)
	check(travel.inside() and world.loot.markers.for_owner(p.inventory.owner_id).size()==2,"Reload returns to the interior front door without discarding either loss")
	losses=world.loot.markers.for_owner(p.inventory.owner_id)
	var newest: Node3D=world.loot.pickups[losses[-1].pickup_id]
	await place(newest.global_position+Vector3(0,.05,1.0))
	check(world.loot.request_pickup(p.inventory,newest),"Newest dungeon loss can be recovered through the original authoritative pickup transaction")
	await frames(3)
	check(world.loot.markers.for_owner(p.inventory.owner_id).size()==1 and not world.inventory_session.loss_hint.text.contains("X 16"),"Recovering the latest loss advances guidance to the older outstanding item")
	await place(Vector3(0,.05,1.5))
	world.inventory_session.live_session=true
	check(travel.focused_door()==null,"Unimplemented live-party travel is gated rather than sharing the local private instance")
	world.inventory_session.live_session=false
	await leave()
	await frames(hz*2)
	var nodes:=transport_node_count()
	for i in range(3):
		await enter()
		await leave()
	await frames(hz*2)
	check(transport_node_count()==nodes and travel.contexts.size()==6 and travel.room_contents.is_empty() and not is_instance_valid(travel.hall_content) and travel._effect.pieces.is_empty() and travel._effect.effects.is_empty(),"Repeated entry/exit retains fixed environment nodes, dormant rentals and shop, and no orphaned transition materials")
	check(p.get_instance_id()==character_id and p.visual.get_instance_id()==visual_id and not paused,"Character identity and live simulation survive all travel, deaths and reloads")
	world.queue_free()
	controls.queue_free()
	await frames(3)
	# Exercise production startup loading before the outer world/interior exist,
	# rather than only reloading an already prepared live session.
	var observe:=func(node: Node):
		if node.get_script()==Session:
			node.ready.connect(func():
				node.save_path=checkpoint
				node.persistence_enabled=true
				node._begin_initial_checkpoint_load())
	node_added.connect(observe)
	var restored_world: Node3D=load("res://scenes/main.tscn").instantiate()
	restored_world.dungeon_enemies_enabled=false
	restored_world.inventory_persistence_enabled=false
	restored_world.world_memory_enabled=false
	restored_world.district_life_enabled=false
	restored_world.boss_encounters_enabled=false
	root.add_child(restored_world)
	node_added.disconnect(observe)
	await frames(15)
	var restored_session: Node=restored_world.inventory_session
	check(restored_session._checkpoint_usable and not restored_session._checkpoint_pending and restored_world.dungeon_travel.inside(),"Fresh startup restores a dungeon save after its destination and support are prepared")
	check(restored_world.player.is_on_floor() and restored_world.loot.markers.for_owner("local").size()==2 and restored_world.player.controls.gameplay_enabled,"Fresh dungeon startup restores both recoverable losses and a playable character")
	restored_session.persistence_enabled=false
	restored_world.queue_free()
	await frames(3)
	print("Dungeon foundation: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
