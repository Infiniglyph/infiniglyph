extends SceneTree
## Real autonomous traffic, collisions, pose budgets and neighborhood turnover.
var world: Node3D
var failures := 0
var checks := 0

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

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.set_physics_process(false)
	world.player.visual.retrieval.enabled = false
	world.controls.set_gameplay_enabled(false)
	world.greefer.think_enabled = false
	await frames(4)
	var life: Node3D = world.district_life
	var moved: Dictionary = {}
	var observed: Dictionary = {}
	var peak_people := 0
	var peak_vehicles := 0
	var bad := 0
	var walkers_moved := 0
	for at: Vector3 in [Vector3(192,0.05,128),Vector3(-256,0.05,-192),Vector3(10,0.05,-512),Vector3(512,0.05,320),Vector3(10,0.05,-930),Vector3(192,0.05,128)]:
		world.player.global_position = at
		life.refresh_active()
		await frames(3)
		var starts: Dictionary = {}
		for vehicle: CharacterBody3D in life.vehicles.values(): starts[vehicle.record.id] = vehicle.global_position
		var walker_starts: Dictionary = {}
		for resident: CharacterBody3D in life.people.values(): walker_starts[resident.record.id] = resident.global_position
		for i in range(360):
			await frames(1)
			peak_people = maxi(peak_people,life.people.size())
			peak_vehicles = maxi(peak_vehicles,life.vehicles.size())
			for vehicle: CharacterBody3D in life.vehicles.values():
				observed[vehicle.record.id] = true
				if not starts.has(vehicle.record.id): starts[vehicle.record.id] = vehicle.global_position
				if starts.has(vehicle.record.id) and vehicle.global_position.distance_to(starts[vehicle.record.id])>3: moved[vehicle.record.id] = true
				if not vehicle.global_position.is_finite() or vehicle.global_position.y< -15: bad += 1
			# Neighborhood construction is deliberately spread over frames. Start
			# each journey observation when its body actually arrives, not frame 3.
			for resident: CharacterBody3D in life.people.values():
				if not walker_starts.has(resident.record.id): walker_starts[resident.record.id] = resident.global_position
		for resident: CharacterBody3D in life.people.values():
			if walker_starts.has(resident.record.id) and resident.global_position.distance_to(walker_starts[resident.record.id])>1: walkers_moved += 1
		check(life.people.size()<=life.resident_budget and life.vehicles.size()<=life.vehicle_budget,"Bounded live neighborhood at "+str(at))
	check(moved.size()>10 and observed.size()>25,"Autonomous traffic travels across multiple neighborhoods")
	check(walkers_moved>10,"Residents walk actual supported routes")
	check(bad==0,"No traffic falls through the map or develops invalid transforms")
	# A directly placed body uses the same envelope/sweep as traffic and driving.
	var vehicle: CharacterBody3D = life.vehicles.values()[0]
	vehicle.has_driver = false
	vehicle.global_position = Vector3(190,0.1,128)
	vehicle.rotation.y = PI*0.5
	var barrier := StaticBody3D.new()
	world.add_child(barrier)
	barrier.position = Vector3(199,1.5,128)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4,3,12)
	shape.shape = box
	barrier.add_child(shape)
	await frames(2)
	vehicle.signed_speed = 18
	await frames(40)
	check(vehicle.position.x<199-vehicle.dimensions.z*0.45,"Vehicle sweep cannot pass through a solid road obstacle")
	barrier.queue_free()
	print("TRAFFIC FLOW: ",checks," checks, ",failures," failures; observed=",observed.size()," moved=",moved.size()," peak_people=",peak_people," peak_vehicles=",peak_vehicles)
	world.queue_free()
	await frames(2)
	quit(1 if failures else 0)
