extends SceneTree
## Native, uncapped frame samples; run separately from other test processes.
var world: Node3D
var label := "baseline"
var memory_enabled := true
var paired := false

func _initialize() -> void:
	if "--headless" in OS.get_cmdline_args():
		push_error("World performance capture requires a native display.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg=="--disable-memory": memory_enabled = false
		if arg=="--paired": paired = true
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await process_frame

func sample(title: String) -> void:
	await frames(90)
	var times: Array[float] = []
	var process := 0.0
	var physics := 0.0
	var calls := 0.0
	for i in range(180):
		var start := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-start)/1000.0)
		process += Performance.get_monitor(Performance.TIME_PROCESS)*1000
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	print("WORLD PERFORMANCE: ",JSON.stringify({"label":label,"view":title,"frame_ms":times[90],"p95_ms":times[171],"process_ms":process/180,"physics_ms":physics/180,"draw_calls":calls/180,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"outdoors":world.population.active_residents.size()}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/performance_"+label+"_"+title+".png")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world = load("res://scenes/main.tscn").instantiate()
	world.world_memory_enabled = memory_enabled
	root.add_child(world)
	world.population.population_seed = 1893
	if paired: world.population.max_outdoors = 44
	world.controls.gameplay_enabled = false
	world.player.set_physics_process(false)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 65
	DirAccess.make_dir_recursive_absolute("res://captures")
	for view in [["plaza",Vector3(0,3,15),Vector3(0,1,-20),Vector3(0,0,8)],["boulevard",Vector3(0,4,-24),Vector3(0,14,-65),Vector3(0,0,-28)],["skyline",Vector3(0,70,32),Vector3(0,14,-30),Vector3(0,65,24)]]:
		camera.position = view[1]
		camera.look_at(view[2])
		world.player.position = view[3]
		if paired:
			for optimized: bool in [false,true]:
				world.world_memory.set_attention_enabled(optimized)
				await sample(view[0]+("_npc_attention" if optimized else "_full_updates"))
		else: await sample(view[0])
	world.population.hide()
	world.population.set_physics_process(false)
	for resident: CharacterBody3D in world.population.residents: resident.set_physics_process(false)
	await sample("skyline_no_population")
	world.queue_free()
	await frames(2)
	quit()
