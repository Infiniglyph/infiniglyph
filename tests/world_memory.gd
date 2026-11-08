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

func elements(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() if indices!=null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
	return total

func wait_world(retrieval: Node, profile: String) -> bool:
	var deadline := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline:
		if retrieval.status=="TED-RAG live" and not retrieval.last_world_decision.is_empty() and retrieval.last_world_decision.profiles[0]==profile: return true
		OS.delay_msec(10)
		await process_frame
	return false

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.population.population_seed = 1893
	world.sparring_partner.visual.retrieval.enabled = false
	await ticks(25)
	var memory: Node3D = world.world_memory
	check(memory.ready_for_queries and memory.cells.size()>20,"The physical city builds a spatial render cache")
	print("WORLD CACHE: ",memory.source_count," source meshes, ",memory.batch_count," retained/compiled batches")
	check(memory.batch_count<memory.source_count*0.85,"Static city presentation removes at least fifteen percent of mesh batches")
	check(memory.residents.size()==100,"All resident identities remain in world memory")
	var sources := 0
	var batches := 0
	var lost := 0
	var source_elements := 0
	var batch_elements := 0
	var bounds_ok := true
	for cell: Dictionary in memory.cells.values():
		var rendered_bounds := AABB()
		var first := true
		for source: MeshInstance3D in cell.sources:
			sources += 1
			source_elements += elements(source.mesh)
			if source.visible and not source in cell.batches: lost += 1
		for batch: MeshInstance3D in cell.batches:
			batches += 1
			batch_elements += elements(batch.mesh)
			var bounds := batch.global_transform*batch.get_aabb()
			rendered_bounds = bounds if first else rendered_bounds.merge(bounds)
			first = false
			if not batch.visible or batch.mesh==null: lost += 1
		bounds_ok = bounds_ok and rendered_bounds.position.is_equal_approx(cell.bounds.position) and rendered_bounds.end.is_equal_approx(cell.bounds.end)
	check(sources==memory.source_count and batches==memory.batch_count and lost==0,"Every compiled source belongs to a retained visible cache batch")
	check(source_elements==batch_elements and bounds_ok,"The render cache preserves all triangle/line elements and world-space bounds")
	check(not memory.retrieve(Vector3(0,1,0),10).is_empty() and memory.retrieve(Vector3(10000,0,0),10).is_empty(),"Spatial retrieval selects only cells intersecting the requested neighborhood")
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
	world.start_menu.open_menu()
	var before: float = world.population.elapsed
	await ticks(30)
	check(not paused and world.population.elapsed>before,"World memory and resident time stay live behind menus")
	world.queue_free()
	await ticks(2)
	print("World memory verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
