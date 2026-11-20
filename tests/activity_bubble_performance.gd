extends SceneTree
## Native paired frame/draw measurements. Run alone, never as an FPS assertion.
var world: Node3D
var results: Array[Dictionary]=[]
var fixed_census:=false
func _initialize() -> void:
	if "--headless" in OS.get_cmdline_args(): push_error("Native display required"); quit(2); return
	fixed_census="--fixed-census" in OS.get_cmdline_user_args()
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await process_frame
func sample(view: String,enabled: bool) -> void:
	var bubble: Node=world.code_form_activity
	bubble.enabled=enabled; bubble.refresh(true); bubble.apply_scenery_ranges()
	world.population.advance_simulation_lod(.25)
	world.district_life.refresh_active()
	await frames(60)
	var times: Array[float]=[]
	var calls:=0.0; var physics:=0.0; var process:=0.0
	for i in range(96):
		var start:=Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec()-start)/1000.0)
		calls+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		physics+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		process+=Performance.get_monitor(Performance.TIME_PROCESS)*1000
	times.sort()
	var bodies:=0
	for resident: CharacterBody3D in world.population.active_residents:
		if not resident.virtualized: bodies+=1
	var row:={"view":view,"bubble":enabled,"median_frame_ms":times[48],"p95_frame_ms":times[91],"mean_process_ms":process/96,"mean_physics_ms":physics/96,"draw_calls":calls/96,"physical_city_residents":bodies,"regional_bodies":world.district_life.people.size(),"vehicles":world.district_life.vehicles.size(),"local_citizens":bubble.local_ids.size()}
	results.append(row); print("ACTIVITY NATIVE ",JSON.stringify(row))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/activity-"+("fixed-" if fixed_census else "live-")+view+("-bubble" if enabled else "-baseline")+".png")
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Activity native watchdog"); quit(2))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.population.population_seed=1893
	world.controls.set_gameplay_enabled(false)
	world.player.set_physics_process(false)
	world.camera_rig.set_physics_process(false)
	world.camera_rig.camera.current=false
	var camera:=Camera3D.new(); root.add_child(camera); camera.current=true
	camera.far=1800; camera.fov=65
	world.camera_rig.camera=camera
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for i in range(600):
		await process_frame
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	if fixed_census:
		# Isolate body/range costs from evolving demographics between samples.
		# Normal character physics and rendering continue in both halves.
		world.civilization.simulation_enabled=false
		world.civic_interactions.set_process(false)
		for resident: CharacterBody3D in world.population.residents:
			resident.wait=1e6; resident.indoor_left=1e6; resident.social_cooldown=1e6
		for record: Dictionary in world.district_life.resident_records: record.wait=1e6
		for resident: CharacterBody3D in world.district_life.people.values(): resident.wait=1e6; resident.social_cooldown=1e6
		for record: Dictionary in world.district_life.vehicle_records: record.traffic=false
	for view: Array in [["street",Vector3(0,3,15),Vector3(0,12,-64),Vector3(0,.2,8)],["sky_jump",Vector3(0,220,60),Vector3(0,0,-100),Vector3(0,200,8)]]:
		world.player.position=view[3]; world.player.velocity=Vector3.ZERO
		world.camera_rig.camera.global_position=view[1]
		world.camera_rig.camera.look_at(view[2])
		await sample(view[0],false)
		await sample(view[0],true)
	var file:=FileAccess.open("res://.godot/activity-native-"+("fixed" if fixed_census else "live")+"-profile.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"cpu":OS.get_processor_name(),"engine":Engine.get_version_info().string,"resolution":[root.size.x,root.size.y],"fixed_census":fixed_census,"samples":results,"notes":"Native GL Compatibility, uncapped, paired in the same scene; other desktop processes remain running. Fixed-census mode freezes the civilian clock, exits and errands while retaining normal body physics and rendering; live mode includes evolving AI/crowd density."},"\t")); file.close()
	world.queue_free(); await frames(3); quit()
