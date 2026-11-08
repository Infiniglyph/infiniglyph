extends SceneTree
var failures := 0
var checks := 0
var world: Node3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _initialize() -> void: call_deferred("run")

func district_state() -> Array:
	var district: Node3D = world.get_node("CentralDistrict")
	var result: Array = []
	for mesh: MeshInstance3D in district.find_children("*","MeshInstance3D",true,false):
		var state: Array = [mesh.global_transform,mesh.visible,mesh.cast_shadow,mesh.get_aabb()]
		for surface in range(mesh.mesh.get_surface_count()):
			state.append(mesh.mesh.surface_get_arrays(surface))
			var material: Material = mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				state.append([material.shading_mode,material.albedo_color,material.emission,material.cull_mode,material.roughness,material.metallic])
		result.append(state)
	for light: Light3D in district.find_children("*","Light3D",true,false):
		result.append([light.global_transform,light.visible,light.light_color,light.light_energy,light.shadow_enabled,light.distance_fade_enabled,light.distance_fade_begin,light.distance_fade_shadow,light.distance_fade_length])
	return result

func make_world(attention: bool) -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.world_memory_enabled = attention
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.population.population_seed = 1893
	world.sparring_partner.visual.retrieval.enabled = false
	if not attention: world.player.visual.retrieval.enabled = false
	await ticks(25)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/npc_attention_"+label+".png")

func wait_world(retrieval: Node, profile: String) -> bool:
	var deadline := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline:
		if retrieval.status=="TED-RAG live" and not retrieval.last_world_decision.is_empty() and retrieval.last_world_decision.profiles[0]==profile: return true
		OS.delay_msec(10)
		await process_frame
	return false

func run() -> void:
	await make_world(false)
	var original_map := district_state()
	world.queue_free()
	await ticks(2)
	await make_world(true)
	var memory: Node3D = world.world_memory
	check(memory.ready_for_queries and memory.get_child_count()==0,"NPC attention creates no map meshes or lights")
	check(district_state()==original_map,"NPC attention leaves original map geometry, visibility, materials, shadows and lights unchanged")
	check(memory.residents.size()==100,"All resident identities remain in world memory")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(0,3,15)
	camera.look_at(Vector3(0,2,-20))
	memory.refresh_attention(camera)
	var dormant: CharacterBody3D
	var near := 0
	for resident: CharacterBody3D in world.population.active_residents:
		if not resident.render_relevant and dormant==null: dormant = resident
		if resident.global_position.distance_to(world.player.global_position)<8:
			near += 1
			check(resident.render_relevant and resident.animation_interval==0,"Nearby interaction retains full visual updates")
	check(dormant!=null,"The view can leave distant resident pose work dormant")
	if dormant!=null:
		var at: Vector3 = dormant.global_position
		var visits: int = dormant.visits
		var profile: Dictionary = dormant.profile.duplicate(true)
		var phase: float = dormant.visual.phase
		await ticks(90)
		check(dormant.active and dormant.global_position.distance_to(at)>0.2,"A visually dormant resident continues its real physical journey")
		check(dormant.profile==profile and dormant.visits==visits,"Visual dormancy preserves identity, color and conversation memory")
		camera.position = dormant.global_position+Vector3(0,2,5)
		camera.look_at(dormant.global_position+Vector3.UP)
		memory.refresh_attention(camera)
		check(dormant.render_relevant and dormant.animation_interval==0,"Turning the camera toward a resident restores nearby full-detail animation")
		await ticks(2)
		check(dormant.visual.phase!=phase,"Restored animation catches up with ongoing motion")
	var retrieval: Node = world.player.visual.retrieval
	var deadline := Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline and retrieval.last_world_decision.is_empty():
		OS.delay_msec(10)
		await process_frame
	check(retrieval.status=="TED-RAG live" and not retrieval.last_world_decision.is_empty(),"The existing live TED-RAG worker retrieves a world-detail policy")
	check(retrieval.last_world_decision.has("constraint"),"World policy uses the real TED-RAG weighted constraint builder")
	memory.set_process(false)
	var helper: int = retrieval.process_id
	retrieval.world_context = {"speed":0.2,"crowd":1.0,"combat":0.0}
	check(await wait_world(retrieval,"crowded"),"Crowded streets retrieve the crowd-specific visual budget")
	var crowded_range: float = retrieval.world_policy().near_range
	retrieval.world_context = {"speed":0.3,"crowd":0.3,"combat":1.0}
	check(await wait_world(retrieval,"combat") and retrieval.world_policy().near_range>crowded_range,"Combat retrieves a broader full-detail neighborhood")
	check(retrieval.process_id==helper,"World attention shares the existing motion worker")
	memory.set_process(true)
	var valid := true
	for key: String in retrieval.WORLD_LIMITS:
		var bounds: Vector2 = retrieval.WORLD_LIMITS[key]
		var value: float = retrieval.world_policy()[key]
		valid = valid and value>=bounds.x and value<=bounds.y
	check(valid,"Retrieved attention stays within authored animation-only limits")
	var bad: Dictionary = retrieval.last_decision.duplicate(true)
	bad.world_attention.parameters.near_range = 1000000.0
	check(retrieval.accept_response(bad) and retrieval.world_policy()==retrieval.WORLD_DEFAULTS,"An out-of-range world budget falls back without rejecting valid motion")
	retrieval.enabled = false
	await ticks(2)
	check(retrieval.world_policy()==retrieval.WORLD_DEFAULTS,"Missing or disabled TED-RAG returns immediately to safe local budgets")
	var stable := true
	for view in [[Vector3(0,3,15),Vector3(0,2,-20)],[Vector3(0,4,-24),Vector3(0,14,-65)],[Vector3(0,70,32),Vector3(0,14,-30)],[Vector3(0,25,-64),Vector3(25,15,-64)]]:
		camera.position = view[0]
		camera.look_at(view[1])
		await ticks(12)
		stable = stable and district_state()==original_map
		await shot(str(view[0].y))
	check(stable,"Camera changes around the plaza, boulevard, skyways and tower never modify the map renderer")
	memory.set_attention_enabled(false)
	var full_updates := true
	for resident: CharacterBody3D in world.population.residents:
		full_updates = full_updates and resident.render_relevant and resident.animation_interval==-1
	check(full_updates and district_state()==original_map,"Disabling NPC attention restores original pose scheduling without touching the map")
	memory.set_attention_enabled(true)
	world.start_menu.open_menu()
	var before: float = world.population.elapsed
	await ticks(30)
	check(not paused and world.population.elapsed>before,"World memory and resident time stay live behind menus")
	world.queue_free()
	await ticks(2)
	print("World memory verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
