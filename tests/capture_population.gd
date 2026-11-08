extends SceneTree
## Native city/portrait review with the real live resident simulation.
var world: Node3D
var camera: Camera3D

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/population_"+label+".png")
	print("POPULATION CAPTURE: ",label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.population.population_seed = 1893
	await ticks(30)
	DirAccess.make_dir_recursive_absolute("res://captures")
	camera = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 65
	camera.global_position = Vector3(0,4.8,20)
	camera.look_at(Vector3(0,1.35,-12))
	await ticks(45)
	await shot("plaza")
	var residents: Array = world.population.active_residents.duplicate()
	residents.sort_custom(func(a: CharacterBody3D,b: CharacterBody3D): return a.position.distance_to(Vector3(0,0,6))<b.position.distance_to(Vector3(0,0,6)))
	var resident: CharacterBody3D = residents[0]
	for offset: Vector3 in [Vector3(1.7,0,1),Vector3(-1.7,0,1),Vector3(0,0,2)]:
		var floor: Dictionary = world.population.floor_at(resident.position+offset)
		if not floor.is_empty() and world.population.clear_at(floor.point):
			world.player.position = floor.point
			break
	world.player.velocity = Vector3.ZERO
	await ticks(4)
	world.inventory_session.interact()
	for offset: Vector3 in [Vector3(-3.2,2.6,4.5),Vector3(3.2,2.6,4.5),Vector3(3.2,2.6,-4.5)]:
		var at := resident.global_position+offset
		var ray := PhysicsRayQueryParameters3D.create(resident.global_position+Vector3.UP*1.3,at,1,[world.player.get_rid()])
		if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			camera.global_position = at
			break
	camera.look_at(resident.global_position+Vector3(0.8,1.3,0))
	await ticks(5)
	await shot("greeting")
	var door: Node3D = world.population.entrances[&"building_13"]
	world.inventory_session._resident_time = 0
	world.player.position = door.to_global(Vector3(3,0.045,9))
	world.player.velocity = Vector3.ZERO
	camera.global_position = door.to_global(Vector3(3,2.3,6))
	camera.look_at(door.to_global(Vector3(0,1.25,-0.8)))
	for candidate: CharacterBody3D in world.population.residents:
		if not candidate.active and candidate.profile.color_name=="orange":
			candidate.home_building = door.entrance_id
			candidate.indoor_left = 0
			world.population.service_indoors(0)
			break
	await ticks(290)
	await shot("lobby")
	await ticks(90)
	print("Population native review complete; residents ",world.population.residents.size()," outdoors ",world.population.active_residents.size()," social events ",world.population.social_events," process ms ",Performance.get_monitor(Performance.TIME_PROCESS)*1000," physics ms ",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	world.population.hide()
	world.population.set_physics_process(false)
	for pedestrian: CharacterBody3D in world.population.residents: pedestrian.set_physics_process(false)
	await ticks(120)
	print("Same view without population: process ms ",Performance.get_monitor(Performance.TIME_PROCESS)*1000," physics ms ",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	world.queue_free()
	await ticks(2)
	quit()
