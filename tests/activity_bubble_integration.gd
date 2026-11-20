extends SceneTree
const Store=preload("res://scripts/inventory_store.gd")
var world: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=1) -> void:
	for i in range(count): await physics_frame; await process_frame
func physics_count() -> int:
	var count:=0
	for resident: CharacterBody3D in world.population.active_residents:
		if not resident.virtualized: count+=1
	return count
func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Activity integration watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	world.controls.set_gameplay_enabled(false); world.player.set_physics_process(false)
	for i in range(600):
		await frames()
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	check(world.civilization.registry.active_ids().size()==1122,"The bubble preserves all 1,122 authoritative civilian identities")
	world.civilization.ensure_starter_capital()
	var economy: Node=world.civilian_services.economy
	var issued: int=economy.issued_total
	var bubble: Node=world.code_form_activity
	check(bubble.enabled and bubble.scenery_count>100,"Production city, region, driveway and window batches receive draw-distance budgets")
	var ranges:=true
	for visual: MeshInstance3D in get_nodes_in_group("bubble_scenery"):
		ranges=ranges and visual.visibility_range_end>=384 and visual.visibility_range_end_margin==32
	check(ranges,"Engine-side scenery ranges include geometry bounds and hysteresis")
	world.player.position=Vector3(0,500,0); world.player.velocity=Vector3.ZERO
	bubble.refresh(true)
	for resident: CharacterBody3D in world.population.active_residents: resident.state="walking"; resident.reaction_time=0
	world.population.advance_simulation_lod(.25)
	world.district_life.refresh_active()
	await frames(3)
	check(physics_count()==0 and world.district_life.people.is_empty() and world.district_life.vehicles.is_empty(),"High Sky Jump altitude retires street physics, resident meshes and traffic bodies")
	check(bubble.local_ids.is_empty(),"Street-level logical careers do not become near simply because X/Z match")
	world.civilization.advance_real(1)
	check(world.civilization.autonomy.last_local_steps==0 and world.civilization.autonomy.last_background_steps==2,"An empty 3D bubble spends only two background AI turns")
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(0,100,0),Vector3(0,-10,0),1)
	check(not world.player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Distant scenery culling retains a real landing surface below the player")
	world.player.position=Vector3(0,100,0); world.player.velocity=Vector3(0,-60,0)
	check(world.population.near_activity(Vector3.ZERO),"Falling activates landing-area residents before reaching street level")
	world.player.position=Vector3(0,0,8); world.player.velocity=Vector3.ZERO
	bubble.refresh(true); world.population.advance_simulation_lod(.25)
	check(physics_count()>0 and not bubble.local_ids.is_empty(),"Returning to the street restores nearby physics and full-detail intentions")
	for resident: CharacterBody3D in world.population.active_residents:
		if resident.virtualized:
			resident.state="talking"
			world.population.advance_simulation_lod(.25)
			check(not resident.virtualized,"An ongoing conversation remains protected across the bubble boundary")
			resident.state="walking"
			break
	var properties: Node=world.building_civilization
	properties._process(1)
	check(properties.inspected_shells<properties.descriptors.size()/2,"Building interiors inspect adjacent cells instead of every shell in the world")
	var travel: Node=world.dungeon_travel
	travel._set_location(travel.pyramid_id); bubble.refresh()
	check(bubble.local_ids.is_empty() and not bubble.contains(Vector3.ZERO),"An instanced interior cannot activate exterior citizens at matching coordinates")
	travel._set_location(travel.OUTSIDE); bubble.refresh(true)
	check(not bubble.local_ids.is_empty(),"Leaving the instance reactivates the outdoor bubble")
	world.start_menu.open_menu()
	var before: float=world.civilization.world_seconds
	check(world.civilization.advance_real(1) and world.civilization.world_seconds>before and not paused,"World time continues behind menus with the new scheduler")
	world.start_menu.close_menu()
	check(world.inventory_session.save_checkpoint("user://tests/activity_bubble.json",true) and not Store.load_snapshot("user://tests/activity_bubble.json").is_empty(),"A mixed local/distant population survives full checkpoint validation")
	check(world.inventory_session.load_checkpoint("user://tests/activity_bubble.json") and world.civilization.registry.active_ids().size()==1122 and economy.issued_total==issued,"Save/load preserves identities and never repeats the initial coin influx")
	bubble.enabled=false; bubble.apply_scenery_ranges()
	ranges=true
	for visual: MeshInstance3D in get_nodes_in_group("bubble_scenery"): ranges=ranges and visual.visibility_range_end==0
	check(ranges,"The diagnostic switch restores unlimited scenery range without rebuilding geometry")
	print("ACTIVITY WORLD ",JSON.stringify({"citizens":1122,"local":bubble.local_ids.size(),"scenery_batches":bubble.scenery_count,"nearby_shells":properties.inspected_shells,"total_shells":properties.descriptors.size()}))
	world.queue_free(); await frames(3)
	print("Activity bubble integration: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
