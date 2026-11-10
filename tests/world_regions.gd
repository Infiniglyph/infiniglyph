extends SceneTree
const Regions = preload("res://scripts/world_regions.gd")
const Shared = preload("res://tests/charge_sparring.gd")
var world: Node3D
var region: Node3D
var actor: CharacterBody3D
var input: Shared.Intent
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

func floor_at(at: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at-Vector3.UP*2,1,[actor.get_rid()]))

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	region = world.wider_world
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.greefer.think_enabled = false
	input = Shared.Intent.new()
	input.source = world.controls
	root.add_child(input)
	actor.controls = input
	actor.set_collision_mask_value(3,false) # Open-road traversal fixture, not NPC collisions.
	world.camera_rig.controls = input
	world.camera_rig.yaw = 0
	await frames(4)
	print("REGION: ",region.counts," chunks=",region.chunks.size()," lights=",region.lights.size()," build_ms=",region.build_ms)
	check(region.chunks.size() == 81 and Regions.HALF_EXTENT*2 == 2304,"Continuous region spans 2.304 km in both directions in 81 stable chunks")
	check(world.camera_rig.camera.far == 1800,"Gameplay camera can see the expanded skyline from aerial exploration height")
	check(region.counts.city>150 and region.counts.homes>250 and region.counts.farms>10 and region.counts.trees>200,"Dense urban blocks transition into housing, farms and woods")
	var samples := 0
	var supported := 0
	for x in range(-1104,1105,48):
		for z in range(-1104,1105,48):
			if absf(x)<112 and absf(z)<112: continue
			var at := Vector3(x,Regions.height_at(x,z),z)
			var hit := floor_at(at)
			samples += 1
			if not hit.is_empty(): supported += 1
	check(samples == supported,"Terrain provides real support throughout the world, including chunk seams (%d probes)" % samples)
	var meshes := 0
	var colliders := 0
	var invalid := 0
	for chunk: Node3D in region.chunks.values():
		meshes += 1
		if chunk.mesh_instance.mesh.get_surface_count()>2 or chunk.mesh_instance.position != Vector3.ZERO: invalid += 1
		for volume: Dictionary in chunk.volumes:
			colliders += 1
			if volume.collider.disabled or volume.collider.shape == null or volume.collider.get_parent() != chunk.body: invalid += 1
	check(invalid == 0 and colliders>2500 and meshes == 81,"Architecture is opaque spatial batches with enabled matching solid volumes")
	var raised_farms := 0
	for chunk: Node3D in region.chunks.values():
		for volume: Dictionary in chunk.volumes:
			if volume.kind == "FarmFoundation" and volume.collider.shape.size.y>0.65: raised_farms += 1
	check(raised_farms == 0,"Rural building pads meet the terrain without tall foundations or hovering homes")
	var roof_hits := 0
	for building: Dictionary in region.buildings:
		var top: Vector3 = building.point+Vector3.UP*building.size.y
		var hit := floor_at(top)
		if not hit.is_empty() and hit.position.y>=top.y-0.15: roof_hits += 1
	check(roof_hits == region.buildings.size(),"Every added building has a solid roof (%d buildings)" % region.buildings.size())
	var lit := true
	for light: SpotLight3D in region.lights:
		if light.light_color != preload("res://scripts/neon.gd").ORANGE or light.light_energy<=0 or not light.distance_fade_enabled: lit = false
	check(lit and region.lights.size()>60,"Orange fixtures have real local lights with engine distance fading")
	actor.position = Vector3(0,0.05,-104)
	actor.velocity = Vector3.ZERO
	input.move = Vector2.UP
	input.boost = true
	await frames(hz*2)
	check(actor.position.z> -112 and not region.gates[0].opened,"Visible closed road gate blocks ordinary travel before the first confrontation")
	input.move = Vector2.ZERO
	var encounter: Node = world.boss_encounter
	encounter.start(true)
	encounter.register_contact()
	actor.weapon_combat.health = 1
	actor.receive_combat_hit(10000,world.greefer.combat_point(),world.greefer,{"damage":10000})
	await frames(hz*2)
	var open := true
	for gate: Node3D in region.gates:
		if not gate.opened or gate.opening<0.99: open = false
	check(open and encounter.can_progress() and encounter.progress.first_outcome == "defeat","An actual first-fight defeat opens all four roads without requiring a victory")
	var bad_roads := 0
	var road_samples := 0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.get_child(0).shape
	query.collision_mask = 1
	query.exclude = [actor.get_rid(),world.greefer.get_rid()]
	query.margin = 0.001
	var roads := [
		[Vector3(0,0,-82),Vector3(0,0,-256)],
		[Vector3(0,0,86),Vector3(0,0,256)],
		[Vector3(68,0,16),Vector3(120,0,16),Vector3(136,0,0),Vector3(256,0,0)],
		[Vector3(-68,0,16),Vector3(-120,0,16),Vector3(-136,0,0),Vector3(-256,0,0)],
		[Vector3(0,0,-512),Vector3(512,0,-512),Vector3(512,0,512),Vector3(-512,0,512),Vector3(-512,0,-512),Vector3(0,0,-512)],
		[Vector3(0,0,-1024),Vector3(512,0,-1024),Vector3(512,0,-768),Vector3(0,0,-768),Vector3(0,0,-1024)]]
	for road: Array in roads:
		for segment in range(road.size()-1):
			var length: float = road[segment].distance_to(road[segment+1])
			for i in range(ceili(length/4)+1):
				var at: Vector3 = road[segment].lerp(road[segment+1],float(i)/ceili(length/4))
				at.y = Regions.surface_at(at.x,at.z)
				var hit := floor_at(at)
				road_samples += 1
				if hit.is_empty():
					bad_roads += 1
					continue
				query.transform = Transform3D(Basis.IDENTITY,hit.position+Vector3.UP*1.0)
				if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
					bad_roads += 1
					if bad_roads<5: print("BLOCKED ROAD: ",at)
	check(bad_roads == 0,"All four hub exits and interconnected urban/residential/country road loops provide capsule clearance (%d probes)" % road_samples)
	actor.position = Vector3(0,0.05,-104)
	actor.velocity = Vector3.ZERO
	actor.fall_damage.reset()
	input.move = Vector2.UP
	input.boost = true
	var reached := {"city":false,"suburb":false,"country":false,"bridge":false}
	var fell := false
	for i in range(hz*100):
		await frames(1)
		if actor.position.y< -1: fell = true
		if actor.position.z< -160: reached.city = true
		if actor.position.z< -470: reached.suburb = true
		if actor.position.z< -730: reached.country = true
		if actor.position.z< -905: reached.bridge = true
		if actor.position.z< -1044: break
	input.move = Vector2.ZERO
	check(reached.city and reached.suburb and reached.country and reached.bridge and actor.position.z< -1044 and not fell,"Real sprint traverses hub gate, city, suburbs, ravine bridge and country lookout without gaps")
	check(is_equal_approx(actor.boost_speed,10.2) and actor.weapon_combat.psi_meter == 0,"Existing sprint speed and free movement/exhaustion rules are preserved")
	# A saved first victory uses the same gate; a rematch cannot close roads.
	encounter.progress.first_outcome = "victory"
	encounter.progress.first_victory = true
	encounter.progress.wins = 1
	encounter.progress.last_outcome = "victory"
	encounter.progression_changed.emit()
	check(region.gates[0].opened,"First victory also keeps the outward route open")
	var path := "user://outer_world_progress.json"
	check(encounter.save_checkpoint(path),"Outward access uses the existing owner-scoped encounter journal")
	encounter.progress.intro_completed = false
	for gate: Node3D in region.gates: gate.refresh()
	check(encounter.load_checkpoint(path) and region.gates[0].opened,"Loading completed encounter progress refreshes gates without another fight")
	encounter.start(true)
	encounter.finish(false)
	check(region.gates[0].opened and encounter.can_progress(),"Losing a rematch never closes the expanded world")
	check(world.population.residents.size() == 100 and not paused,"Original one hundred resident identities and live world remain intact")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Outer world verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
