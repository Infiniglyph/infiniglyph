extends SceneTree
## Real shop portals, independent worlds and cold checkpoints with display-top loot.
const Catalog=preload("res://scripts/item_catalog.gd")
const Store=preload("res://scripts/inventory_store.gd")
const Hall=preload("res://scripts/glyphic_wonders_hall.gd")
const Regions=preload("res://scripts/world_regions.gd")
const Chunk=preload("res://scripts/world_chunk.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var controls: Intent
var checks:=0
var failures:=0
var inside_save:="user://tests/wonders_inside.json"
var outside_save:="user://tests/wonders_outside.json"
var census_only:=false

func _initialize() -> void:
	Engine.physics_ticks_per_second=60
	Engine.max_physics_steps_per_frame=1
	census_only="--census-only" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame

func setup() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.district_life_enabled=census_only
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	root.add_child(world)
	p=world.player; travel=world.dungeon_travel
	controls=Intent.new(); root.add_child(controls)
	controls.interaction_context=world.inventory_session
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	for i in range(300):
		if travel.ready_for_travel and is_instance_valid(world.civilization) and world.civilization.ready_for_simulation: break
		await frames(1)
	world.civilization.simulation_enabled=false
	await frames(5)

func place(at: Vector3) -> void:
	p.global_position=at; p.velocity=Vector3.ZERO
	p.fall_damage.reset(); p.visual.rebase_after_phase()
	await frames(15)

func finish_transition() -> void:
	for i in range(240):
		if not travel.busy: break
		await frames(1)
	check(not travel.busy and not p.transition_locked and controls.gameplay_enabled,"Shop reconstruction finishes with the same responsive player")
	await frames(8)

func enter() -> void:
	await place(world.wider_world.glyphic_wonders.arrival_anchor.global_position)
	await frames(35)
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_G; key.pressed=true
	controls._unhandled_input(key)
	await frames(2)
	check(travel.busy,"G at the storefront starts explicit shop entry")
	await finish_transition()
	check(travel.is_wonders(),"The portal selects the player's persistent shop context")

func leave() -> void:
	await place(Vector3(0,Hall.FLOOR+.05,64))
	await frames(35)
	controls.set_right_trigger(0); controls.set_right_trigger(1)
	await frames(1)
	check(not travel.busy,"A held bare trigger waits for its release at the shop exit")
	controls.set_right_trigger(0)
	await frames(2)
	check(travel.busy,"A released RT tap starts the existing shop exit interaction")
	await finish_transition()

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Glyphic Wonders travel watchdog"); quit(2))
	await setup()
	if census_only:
		var legacy:=Regions.new()
		var scratch:=Chunk.new()
		var lot:=Vector3(-96,0,-608)
		legacy.build_suburb(scratch,lot,Regions.code(floori(lot.x/64),floori(lot.z/64)))
		var retained: Array=[]
		var first: int=-1
		for i in range(world.wider_world.buildings.size()):
			var data: Dictionary=world.wider_world.buildings[i]
			if not legacy.buildings.has(data): continue
			if first<0: first=i
			retained.append(data)
		check(not retained.is_empty() and retained==legacy.buildings and world.wider_world.buildings.slice(first,first+retained.size())==retained,"Replaced scenery retains the original building metadata1:1 in contiguous generator order")
		scratch.free(); legacy.free()
		check(world.district_life.resident_records.size()==780 and world.district_life.vehicle_records.size()==238,"Replacing the storefront lot preserves all780 regional people and238 driver slots")
		check(world.civilization.registry.active_ids().size()==1122,"The original1122-person persistent civilian census remains unchanged")
		world.free(); controls.free()
		await frames(2)
		print("Glyphic Wonders census: ",checks," checks, ",failures," failures")
		quit(1 if failures else 0)
		return
	check(travel.contexts.size()==6 and travel.is_wonders(travel.wonders_id) and not is_instance_valid(travel.hall_content),"Actual world prepares a dormant sixth context without loading the grand hall")
	check(travel.hall_support.get_child_count()==Hall.collision_layout().size() and travel.contexts[travel.wonders_id].get_world_3d()!=p.get_world_3d(),"The unloaded shop has exact collision support in a separate World3D")
	check(is_instance_valid(world.glyphic_wonders) and not is_instance_valid(world.glyphic_wonders.hall),"The logical shop service exists independently of its unloaded visual hall")
	var sword: Resource=Catalog.create(&"eturnull_manuscript")
	p.inventory.add_item(sword)
	world.loot.request_equip(p.inventory,&"down",sword.instance_id)
	p.combat.selected_slot=&"down"; p.combat.sheathed=false
	p.weapon_combat.sync_rig()
	var actor_id:=p.get_instance_id()
	var inventory_before: Dictionary=p.inventory.serialize()
	p.weapon_combat.health=745
	world.camera_rig.yaw=.73
	await enter()
	check(world.glyphic_wonders.hall==travel.hall_content and is_instance_valid(world.glyphic_wonders.merchant) and world.glyphic_wonders.displays.size()<=12,"Lazy construction attaches the real merchant and bounded merchandise displays to the hall")
	var stock_before: Dictionary=world.glyphic_wonders.serialize()
	check(p.get_instance_id()==actor_id and p.inventory.serialize()==inventory_before and p.health==745 and not p.combat.sheathed,"Entry preserves actor identity, owned gear, drawn Manuscript and health")
	check(absf(world.camera_rig.yaw-.73)<.001 and p.get_world_3d()==travel.hall_content.get_world_3d() and not travel.outside_root.visible,"Entry retains facing while rendering only the independent hall")
	controls.jump_requested=true; await frames(5)
	controls.jump_requested=true; await frames(2)
	check(p.air_step_count>0 and p.dodge.start(Vector3.RIGHT),"Sky Jump and phase dodge retain the shared movement system inside the shop")
	p.dodge.cancel()
	var pedestal: Marker3D=travel.hall_content.pedestals[0]
	await place(pedestal.global_position)
	var material: Resource=Catalog.create(&"light_shard")
	p.inventory.add_item(material)
	var drop_id: String=material.instance_id
	check(world.loot.request_drop(p.inventory,drop_id,1,p.global_position+Vector3(.8,0,0)),"A real owned item can be dropped onto a merchandise display surface")
	await frames(4)
	var drop: Node3D
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.item_instance.instance_id==drop_id: drop=pickup
	check(is_instance_valid(drop) and drop.location_id==travel.wonders_id and absf(drop.global_position.y-Hall.PEDESTAL_TOP)<.15,"Display-top loot belongs to the shop instance at its real support height")
	check(world.inventory_session.save_checkpoint(inside_save,true),"An interior checkpoint saves the shop position and furniture-supported item together")
	await leave()
	check(travel.active_location==travel.OUTSIDE and not is_instance_valid(travel.hall_content) and travel.hall_support.collision_layer==1,"Exit unloads all hall visuals while restoring exact dormant collision support")
	check(not is_instance_valid(world.glyphic_wonders.hall) and not is_instance_valid(world.glyphic_wonders.merchant) and world.glyphic_wonders.displays.is_empty() and world.glyphic_wonders.serialize()==stock_before,"Unloading detaches merchant and display references without rerolling persistent stock")
	check(p.global_position.distance_to(world.wider_world.glyphic_wonders.arrival_anchor.global_position)<.2 and p.get_world_3d()==travel.outside_root.get_world_3d(),"The same player returns to the correct storefront rather than the pyramid")
	check(not world.loot.supported_position(drop.global_position,travel.wonders_id).is_empty() and not world.loot.request_pickup(p.inventory,drop),"Dormant display drops remain supported and cannot be collected from outdoors")
	check(world.inventory_session.save_checkpoint(outside_save,true),"The outdoor checkpoint includes persistent unloaded-shop loot")
	await enter()
	world.loot.death_drop_probability=0
	p.weapon_combat.receive_environment_damage(10000)
	await frames(5)
	check(not travel.inside() and p.health==1000 and p.global_position.distance_to(world.wider_world.glyphic_wonders.arrival_anchor.global_position)<.2,"Default shop death revives outside the storefront and unloads the hall")
	world.free(); controls.free()
	await frames(4)
	await setup()
	check(not is_instance_valid(travel.hall_content),"A fresh world has never rendered the grand hall")
	check(world.inventory_session.load_checkpoint(outside_save) and not is_instance_valid(travel.hall_content),"Cold outdoor restore validates display-top drops without instantiating the hall")
	var recovered: Node3D
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.item_instance.instance_id==drop_id: recovered=pickup
	check(is_instance_valid(recovered) and recovered.location_id==travel.wonders_id and absf(recovered.global_position.y-Hall.PEDESTAL_TOP)<.15,"Cold restoration retains the original item identity and display support height")
	await frames(4)
	check(world.inventory_session.load_checkpoint(inside_save) and travel.is_wonders() and is_instance_valid(travel.hall_content),"Cold interior checkpoint rebuilds the correct hall and restores the supported player position")
	check(p.is_on_floor() or absf(p.global_position.y-Hall.PEDESTAL_TOP)<.2,"Saved display-top player reconstruction remains above the real pedestal")
	check(not paused,"Shop travel, death and checkpoint work never pause simulation")
	world.free(); controls.free()
	await frames(2)
	print("Glyphic Wonders travel: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
