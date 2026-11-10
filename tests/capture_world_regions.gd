extends SceneTree
var world: Node3D
var camera: Camera3D

func frames(count: int) -> void:
	for i in range(count): await process_frame

func shot(label: String, from: Vector3, to: Vector3) -> void:
	camera.position = from
	camera.look_at(to)
	world.player.position = Vector3(from.x,world.wider_world.surface_at(from.x,from.z)+0.05,from.z)
	await frames(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/world_"+label+".png")
	print("CAPTURE: ",label)

func sample(label: String) -> void:
	await frames(30)
	var times: Array[float] = []
	var calls := 0.0
	var physics := 0.0
	for i in range(60):
		var before := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-before)/1000.0)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
	times.sort()
	print("PERFORMANCE: ",JSON.stringify({"view":label,"median_ms":times[30],"p95_ms":times[57],"draw_calls":calls/60,"physics_ms":physics/60,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"outdoors":world.population.active_residents.size()}))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute("res://captures")
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.player.set_physics_process(false)
	world.greefer.think_enabled = false
	world.controls.set_gameplay_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = Camera3D.new()
	camera.fov = 68
	camera.far = 1800
	world.add_child(camera)
	camera.current = true
	await shot("hub_gate_closed",Vector3(15,4,-100),Vector3(0,4,-114))
	world.boss_encounter.progress.intro_completed = true
	world.boss_encounter.progression_changed.emit()
	for i in range(130): await physics_frame
	await shot("hub_gate_open",Vector3(0,3,-104),Vector3(0,7,-160))
	await shot("urban_street",Vector3(0,3,-210),Vector3(0,12,-360))
	await shot("city_overview",Vector3(325,190,250),Vector3(0,10,-260))
	await shot("suburbs",Vector3(90,25,-544),Vector3(30,2,-610))
	await shot("country_bridge",Vector3(14,7,-812),Vector3(0,0,-875))
	await shot("country_vista",Vector3(130,90,-900),Vector3(-120,15,-1010))
	var farm: Dictionary = {}
	for building: Dictionary in world.wider_world.buildings:
		if building.region == "farm" and building.point.z< -730 and absf(building.point.x)<600:
			farm = building
			break
	if not farm.is_empty(): await shot("farm",farm.point+Vector3(30,14,30),farm.point+Vector3.UP*3)
	await shot("lookout",Vector3(0,3,-1035),Vector3(0,20,-1100))
	if "--performance" in OS.get_cmdline_user_args():
		camera.position = Vector3(0,3,14)
		camera.look_at(Vector3(0,15,-65))
		world.player.position = Vector3(0,0.05,6)
		await sample("expanded_hub")
		camera.position = Vector3(0,3,-526)
		camera.look_at(Vector3(0,5,-660))
		world.player.position = Vector3(0,0.05,-526)
		await sample("suburbs")
		camera.position = Vector3(0,4,-1000)
		camera.look_at(Vector3(0,18,-1100))
		world.player.position = Vector3(0,0.05,-1000)
		await sample("country")
	world.queue_free()
	await frames(2)
	if "--performance" in OS.get_cmdline_user_args():
		world = load("res://scenes/main.tscn").instantiate()
		world.inventory_persistence_enabled = false
		world.wider_world_enabled = false
		root.add_child(world)
		world.player.visual.retrieval.enabled = false
		world.player.set_physics_process(false)
		world.controls.set_gameplay_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		camera = Camera3D.new()
		world.add_child(camera)
		camera.current = true
		camera.fov = 68
		camera.position = Vector3(0,3,14)
		camera.look_at(Vector3(0,15,-65))
		await sample("hub_without_expansion")
		world.queue_free()
		await frames(2)
	print("Outer world native review complete")
	quit()
