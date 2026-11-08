extends SceneTree
## Real lobby openings and camera-visible streaming safeguards.
var world: Node3D
var population: Node3D
var checks := 0
var failures := 0

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

func ray(a: Vector3, b: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1,[world.player.get_rid(),world.sparring_partner.get_rid()]))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	population = world.population
	population.population_seed = 1893
	await ticks(20)
	var openings := 0
	var jambs := 0
	var screens := 0
	var supported := 0
	for door: Node3D in population.entrances.values():
		if ray(door.to_global(Vector3(0,1.2,0.7)),door.to_global(Vector3(0,1.2,-0.8))).is_empty(): openings += 1
		if not ray(door.to_global(Vector3(1.9,1.2,0.7)),door.to_global(Vector3(1.9,1.2,-0.8))).is_empty(): jambs += 1
		if not ray(door.to_global(Vector3(0,1.2,1)),door.to_global(Vector3(0,1.2,-3.15))).is_empty(): screens += 1
		if not population.floor_at(door.concealed()).is_empty() and population.clear_at(door.concealed()): supported += 1
	check(openings==22,"Every lobby has a real open doorway instead of a painted door on a solid box")
	check(jambs==22 and screens==22,"Door jambs and privacy screens remain physical")
	check(supported==22,"Every concealed indoor handoff has supported full-body clearance")
	var resident: CharacterBody3D
	for candidate: CharacterBody3D in population.residents:
		if not candidate.active:
			resident = candidate
			break
	var door: Node3D = population.entrances[resident.home_building]
	resident.visits = 4
	resident.indoor_left = 0
	world.camera_rig.set_physics_process(false)
	var camera: Camera3D = world.camera_rig.camera
	# SpringArm3D updates its children internally even when the rig script stops.
	# Detach this test camera so each staged view stays where the test puts it.
	camera.reparent(root)
	camera.global_position = door.to_global(Vector3(-0.9,1.35,-3.15))
	camera.look_at(door.concealed()+Vector3.UP)
	check(not population.hidden_from_player(door.concealed()),"A player looking inside the lobby can see the concealed handoff point")
	population.service_indoors(0)
	check(not resident.active,"An indoor resident never appears at a handoff point the player can see")
	camera.global_position = door.to_global(Vector3(0,1.5,3.5))
	camera.look_at(door.concealed()+Vector3.UP)
	check(population.hidden_from_player(door.concealed()),"The real privacy screen occludes the handoff from the street")
	var player_position: Vector3 = world.player.position
	world.player.position = door.concealed()
	await ticks(2)
	population.service_indoors(0)
	check(not resident.active,"A hidden handoff occupied by the player's body cannot spawn a resident")
	world.player.position = player_position
	await ticks(2)
	population.service_indoors(0)
	check(resident.active and resident.transit==&"exiting" and resident.collision_layer==4,"An unseen resident activates physically behind the screen")
	check(not door.available(world.player),"One resident owns the doorway passage at a time")
	for i in range(900):
		await ticks(1)
		if resident.exits>0: break
	check(resident.exits>0 and resident.transit==&"outdoor","The resident walks the full lobby route onto the street")
	resident.go_to(door.entrance_id)
	var observed := false
	for i in range(1500):
		await ticks(1)
		if resident.transit==&"entering":
			camera.global_position = door.to_global(Vector3(-0.9,1.35,-3.15))
			camera.look_at(door.concealed()+Vector3.UP)
			observed = true
		if resident.transit==&"waiting_hidden": break
	print("OBSERVED ENTRY: observed ",observed," active ",resident.active," entries ",resident.entries," state ",resident.transit," position ",resident.position," hidden ",population.hidden_from_player(resident.position))
	check(observed and resident.active and resident.entries==0,"A resident entering the lobby stays visible while the player watches")
	camera.global_position = door.to_global(Vector3(0,1.5,3.5))
	camera.look_at(door.concealed()+Vector3.UP)
	await ticks(5)
	check(not resident.active and resident.entries==1 and resident.visits==4,"After passing out of sight, the resident goes indoors and keeps conversation memory")
	check(resident.collision_layer==0 and not resident.visible and not resident.is_physics_processing(),"Indoor pooling leaves no invisible body blocking the lobby")
	world.queue_free()
	camera.queue_free()
	await ticks(2)
	print("Resident entrances verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
