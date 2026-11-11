extends SceneTree
## Native, uncapped diagnostic only. Every ablation is restored; gameplay code
## and personal saves are untouched. Run alone, without --fixed-fps/--headless.
var world: Node3D
var camera: Camera3D
var samples := 120
var output := "res://captures/performance_audit.json"
var rows: Array[Dictionary] = []
var lights: Array[Dictionary] = []
var dynamic_visuals: Array[Dictionary] = []
var glow: CanvasLayer
var baseline_size := Vector2i(1280,720)
var simulation_only := false
var selected_views := PackedStringArray(["hub","urban","suburbs","country"])

func _initialize() -> void:
	if "--headless" in OS.get_cmdline_args() or "--fixed-fps" in OS.get_cmdline_args():
		push_error("Use a native display and real frame time for the performance audit.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): samples = maxi(30,int(arg.trim_prefix("--samples=")))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--views="): selected_views = arg.trim_prefix("--views=").split(",")
		if arg=="--simulation-only": simulation_only = true
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await process_frame

func sample(view: String, variant: String) -> void:
	# Some engine monitors refresh only once a second. Wall time is essential
	# here: 45 frames can be less than a second in the cheaper variants.
	var warm_start := Time.get_ticks_usec()
	var warm_frames := 0
	while warm_frames<45 or Time.get_ticks_usec()-warm_start<1100000:
		await process_frame
		warm_frames += 1
	var times: Array[float] = []
	var physics_ms := 0.0
	var calls := 0.0
	var primitives := 0.0
	var render_cpu_ms := 0.0
	var render_gpu_ms := 0.0
	for i in range(samples):
		var before := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-before)/1000.0)
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	times.sort()
	var row := {"view":view,"variant":variant,"size":[root.size.x,root.size.y],
		"samples":samples,"median_ms":times[samples/2],"p95_ms":times[mini(samples-1,int(samples*0.95))],
		"physics_monitor_ms":physics_ms/samples,
		"render_cpu_ms":render_cpu_ms/samples,"render_gpu_ms":render_gpu_ms/samples,
		"draw_calls":calls/samples,"primitives":primitives/samples,
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"hub_outdoors":world.population.active_residents.size(),
		"regional_people":world.district_life.people.size(),"vehicles":world.district_life.vehicles.size()}
	rows.append(row)
	print("AUDIT: ",JSON.stringify(row))

func collect(node: Node) -> void:
	if node is Light3D:
		lights.append({"node":node,"visible":node.visible,"shadow":node.shadow_enabled})
	if node is GeometryInstance3D:
		var ancestor := node.get_parent()
		while ancestor!=null and ancestor!=world:
			if ancestor is CharacterBody3D:
				dynamic_visuals.append({"node":node,"visible":node.visible})
				break
			ancestor = ancestor.get_parent()
	for child: Node in node.get_children(): collect(child)

func restore() -> void:
	root.size = baseline_size
	camera.far = 1800
	glow.visible = true
	root.disable_3d = false
	for entry: Dictionary in lights:
		entry.node.visible = entry.visible
		entry.node.shadow_enabled = entry.shadow
	for entry: Dictionary in dynamic_visuals: entry.node.visible = entry.visible

func snapshot() -> void:
	lights.clear()
	dynamic_visuals.clear()
	collect(world)
	var shadow_count := 0
	for entry: Dictionary in lights:
		if entry.shadow: shadow_count += 1
	print("AUDIT INVENTORY: lights=",lights.size()," shadow_lights=",shadow_count,
		" dynamic_geometry=",dynamic_visuals.size()," hub_batches=",world.find_child("Metropolis",true,false).render_batches,
		" world_chunks=",world.wider_world.chunks.size())

func simulation_samples(view: String) -> void:
	# Leave bodies, geometry, lights and the rest of the world present. These
	# paired switches measure CPU scheduling, not the value of deleting a crowd.
	world.population.process_mode = Node.PROCESS_MODE_DISABLED
	await sample(view,"hub_simulation_off")
	world.population.process_mode = Node.PROCESS_MODE_INHERIT
	world.district_life.process_mode = Node.PROCESS_MODE_DISABLED
	await sample(view,"regional_simulation_off")
	world.population.process_mode = Node.PROCESS_MODE_DISABLED
	await sample(view,"all_civilian_simulation_off")
	world.population.process_mode = Node.PROCESS_MODE_INHERIT
	world.district_life.process_mode = Node.PROCESS_MODE_INHERIT
	await sample(view,"live_repeat")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = baseline_size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	world.population.population_seed = 1893
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.player.set_physics_process(false)
	world.greefer.think_enabled = false
	world.controls.set_gameplay_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = Camera3D.new()
	camera.fov = 68
	camera.far = 1800
	root.add_child(camera)
	camera.current = true
	glow = world.get_node("NeonGlow")
	print("AUDIT HARDWARE: ",JSON.stringify({"engine":Engine.get_version_info().string,
		"adapter":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),
		"driver":RenderingServer.get_current_rendering_driver_name(),"cpu":OS.get_processor_name(),
		"threads":OS.get_processor_count(),"debug":OS.is_debug_build()}))
	for view: Array in [
		["hub",Vector3(0,3,14),Vector3(0,15,-65),Vector3(0,0.05,6)],
		["urban",Vector3(0,3,-210),Vector3(0,12,-360),Vector3(0,0.05,-210)],
		["suburbs",Vector3(90,8,-544),Vector3(30,2,-610),Vector3(90,0.05,-544)],
		["country",Vector3(14,7,-812),Vector3(0,0,-875),Vector3(0,0.2,-812)]]:
		if not view[0] in selected_views: continue
		camera.position = view[1]
		camera.look_at(view[2])
		world.player.position = view[3]
		world.district_life.refresh_active()
		await frames(90)
		await sample(view[0],"live")
		if simulation_only:
			await simulation_samples(view[0])
			continue
		# A frozen snapshot isolates rendering changes from evolving crowd state.
		# This is confined to this diagnostic process, never a gameplay menu.
		world.process_mode = Node.PROCESS_MODE_DISABLED
		snapshot()
		await sample(view[0],"frozen_baseline")
		glow.visible = false
		await sample(view[0],"no_glow")
		restore()
		for entry: Dictionary in lights: entry.node.shadow_enabled = false
		await sample(view[0],"no_shadows")
		restore()
		for entry: Dictionary in lights: entry.node.visible = false
		await sample(view[0],"no_lights")
		restore()
		for entry: Dictionary in dynamic_visuals: entry.node.visible = false
		await sample(view[0],"no_dynamic_visuals")
		restore()
		camera.far = 450
		await sample(view[0],"far_450")
		restore()
		root.size = Vector2i(640,360)
		await sample(view[0],"640x360")
		restore()
		root.disable_3d = true
		glow.visible = false
		await sample(view[0],"no_3d")
		restore()
		await sample(view[0],"frozen_repeat")
		world.process_mode = Node.PROCESS_MODE_INHERIT
		await sample(view[0],"live_repeat")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Could not write performance audit: "+output)
		quit(2)
		return
	file.store_string(JSON.stringify({"schema":1,"engine":Engine.get_version_info().string,
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"cpu":OS.get_processor_name(),"debug":OS.is_debug_build(),"physics_hz":Engine.physics_ticks_per_second,
		"notes":"Native standalone, VSync off, no fixed fps. Player movement, boss thinking and TED-RAG helper disabled for repeatability. Frozen/stopped variants are diagnostic only. Zero GPU timer means unavailable, not zero cost. Physics monitor is lagged per-tick time, not total physics per rendered frame. Static collision never unloaded. Live crowd counts can change; use live/repeat rows to assess drift. Other desktop applications remain running.","rows":rows},"\t"))
	file.close()
	print("AUDIT SAVED: ",output)
	world.queue_free()
	camera.queue_free()
	await frames(2)
	quit()
