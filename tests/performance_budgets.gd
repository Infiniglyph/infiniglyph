extends SceneTree
## Real scene transitions, graphics controls and bounded work; no FPS assertion.
var world: Node3D
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shadow_count() -> int:
	var count := 0
	for fixture: Node in get_nodes_in_group("street_lights"):
		if fixture.light.shadow_enabled: count += 1
	return count

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/budgets_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
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
	await frames(hz)
	var population: Node3D = world.population
	var life: Node3D = world.district_life
	var graphics: Node = world.graphics
	var menu: CanvasLayer = world.start_menu
	var district: Node3D = world.get_node("CentralDistrict")
	var collider_count := district.find_children("*","CollisionShape3D",true,false).size()
	var batcher: Node3D = district.visual_batches
	check(batcher.source_count>100 and batcher.batch_count<batcher.source_count/2,"Static props are consolidated into small immutable render batches")
	check(shadow_count()<=4,"Default shadow casters stay within the nearby budget")
	graphics.shadow_budget = 0
	graphics.apply_quality()
	check(shadow_count()==0,"Zero shadow budget removes shadow passes")
	var orange_lit := true
	for fixture: Node in get_nodes_in_group("street_lights"):
		orange_lit = orange_lit and fixture.light.visible and fixture.light.light_energy>0
	check(orange_lit,"Every orange streetlight still emits real light without shadows")
	graphics.shadow_budget = 16
	graphics.apply_quality()
	check(shadow_count()==16,"Full quality restores all sixteen streetlight shadow casters")
	menu.open_menu()
	menu.show_settings()
	menu._shadows.value = 2
	menu._glow.value = 0
	menu._resolution.value = 65
	check(not world.get_node("NeonGlow").visible and is_equal_approx(root.scaling_3d_scale,0.65),"Settings change actual glow visibility and 3D rendering resolution")
	check(root.get_visible_rect().size==Vector2(1280,720),"3D scaling leaves the native UI viewport unchanged")
	menu._glow.value = 1
	var material: ShaderMaterial = world.get_node("NeonGlow").get_child(0).material
	check(world.get_node("NeonGlow").visible and material.get_shader_parameter("cheap_glow"),"Soft glow selects the cheaper shader path")
	var path := "user://graphics_test.cfg"
	check(menu.save_settings(path),"Graphics choices save alongside existing settings")
	menu._shadows.value = 16
	menu._resolution.value = 100
	menu._glow.value = 2
	check(menu.load_settings(path) and graphics.shadow_budget==2 and graphics.resolution_percent==65 and graphics.glow_quality==1,"Saved graphics settings restore the actual renderer controls")
	await frames(4)
	menu._resolution.grab_focus()
	await frames(4)
	check(menu._resolution.get_global_rect().intersects(menu._settings.get_global_rect()),"Controller focus scrolls to the graphics controls")
	await capture("settings")
	var elapsed: float = population.elapsed
	await frames(hz/2)
	check(population.elapsed>elapsed and not paused,"Settings never pause population or world time")
	menu.close_menu()
	world.controls.set_gameplay_enabled(false)
	graphics.resolution_percent = 100
	graphics.glow_quality = 2
	graphics.shadow_budget = 4
	graphics.apply_quality()
	var resident: CharacterBody3D = population.active_residents[0]
	var profile: Dictionary = resident.profile.duplicate(true)
	var visits: int = resident.visits
	resident.wait = 0
	resident.reaction_time = 0
	resident.go_to(population.public_places[0])
	var before := resident.global_position
	world.player.global_position = Vector3(0,0.1,-950)
	await frames(hz*2)
	check(resident.active and resident.virtualized and not resident.is_physics_processing() and resident.collision_layer==0,"Far hub residents leave movement physics while retaining their outdoor journey")
	check(resident.global_position.distance_to(before)>0.1 and resident.profile==profile and resident.visits==visits,"Virtual hub travel advances position and preserves identity and conversation memory")
	world.player.global_position = resident.global_position+Vector3(2.5,0,0)
	await frames(hz)
	check(not resident.virtualized and resident.is_physics_processing() and resident.collision_layer==4,"Approaching restores the original physical resident before interaction range")
	resident.set_virtualized(true)
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,2,1)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = resident.global_position+Vector3.UP
	world.add_child(blocker)
	await frames(2)
	check(not resident.set_virtualized(false) and resident.collision_layer==0,"Occupied return space delays restoration without embedding a resident")
	blocker.queue_free()
	await frames(2)
	check(resident.set_virtualized(false) and resident.collision_layer==4,"Restoration succeeds once the physical space is clear")
	var map_stable := collider_count==district.find_children("*","CollisionShape3D",true,false).size()
	for batch: Node in batcher.get_children(): map_stable = map_stable and batch.visible
	check(map_stable,"Travel and quality changes leave every static collider and render batch present")
	world.player.global_position = Vector3(192,0.1,128)
	life.refresh_active()
	var bounded := true
	for i in range(hz*3):
		await frames(1)
		bounded = bounded and life.validation_probes<=12 and life.spawned_this_tick<=2
	check(bounded and not life.people.is_empty(),"Neighborhood spawning spreads construction and route validation across frames")
	var regional: CharacterBody3D = life.people.values()[0]
	var identity: Dictionary = regional.profile.duplicate(true)
	regional.wait = 0
	regional.record.meetings = 0
	before = regional.global_position
	world.player.global_position = regional.global_position+Vector3(110,0,0)
	await frames(hz*2)
	check(is_instance_valid(regional) and regional.virtualized and regional.collision_layer==0,"Distant neighborhood residents also switch to route-record simulation")
	check(regional.global_position.distance_to(before)>0.1 and regional.profile==identity,"Regional virtual travel preserves the same resident identity")
	var observer := Camera3D.new()
	world.add_child(observer)
	observer.global_position = regional.global_position+Vector3(0,3,12)
	observer.look_at(regional.global_position+Vector3.UP)
	observer.current = true
	await frames(hz/2)
	var shown_before: Vector3 = regional.visual.global_position
	var largest_step := 0.0
	for i in range(hz):
		await frames(1)
		var shown_now: Vector3 = regional.visual.global_position
		largest_step = maxf(largest_step,shown_now.distance_to(shown_before))
		shown_before = shown_now
	check(largest_step<0.15,"Visible distant movement interpolates smoothly between route-record updates")
	observer.queue_free()
	world.camera_rig.camera.current = true
	world.player.global_position = regional.global_position+Vector3(2.5,0,0)
	await frames(hz)
	check(not regional.virtualized and regional.collision_layer==4 and regional.is_physics_processing(),"Regional residents safely restore normal collision and movement nearby")
	# A fast approach can anger a resident before its next scheduling refresh.
	regional.set_virtualized(true)
	world.theft_reactions.react(regional,true)
	var key: String = world.theft_reactions.key_for(regional)
	world.theft_reactions.entries[key].anger = world.theft_reactions.enrage_threshold
	blocker = StaticBody3D.new()
	shape = CollisionShape3D.new()
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = regional.global_position+Vector3.UP
	world.add_child(blocker)
	await frames(2)
	check(not world.theft_reactions.begin_fighter(key) and regional.virtualized,"A blocked virtual resident delays combat materialization instead of spawning inside an obstacle")
	blocker.queue_free()
	await frames(2)
	check(world.theft_reactions.begin_fighter(key),"A newly approached virtual resident can enter the full-rate combat pipeline")
	world.theft_reactions.finish_fighter(key,false)
	check(not regional.virtualized and regional.is_physics_processing() and not regional.record.combat,"Combat disengagement restores exactly one physical civilian without retaining virtual updates")
	var traffic: CharacterBody3D
	for candidate: CharacterBody3D in life.vehicles.values():
		if candidate.has_driver:
			traffic = candidate
			break
	check(is_instance_valid(traffic),"Live autonomous traffic remains available")
	if is_instance_valid(traffic):
		var sensor_count: int = traffic.sensor_checks
		var shape_id: int = traffic._probe_box.get_instance_id()
		await frames(hz)
		check(traffic.sensor_checks-sensor_count>0 and traffic.sensor_checks-sensor_count<=15 and traffic._probe_box.get_instance_id()==shape_id,"Traffic reuses its probe and limits sensing without slowing physical simulation")
		check(traffic._wheel_solids.instance_count==traffic.wheel_nodes.size() and traffic._wheel_wires.instance_count==traffic.wheel_nodes.size(),"Wheel instances retain all physical axle positions")
	await capture("street")
	print("PERFORMANCE BUDGETS: ",checks," checks, ",failures," failures at ",hz," Hz")
	world.queue_free()
	await frames(2)
	quit(1 if failures else 0)
