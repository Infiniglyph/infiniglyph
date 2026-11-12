extends SceneTree
## Reproduce occupied-waypoint stalls and crowd orbits in the real hub.
const Contacts = preload("res://tests/resident_contacts.gd")
const Neon = preload("res://scripts/neon.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
var world: Node3D
var population: Node3D
var checks := 0
var failures := 0
var hz := 60

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

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func clear_population() -> void:
	for resident: CharacterBody3D in population.residents:
		resident.deactivate()
		resident.indoor_left = INF
	population.active_residents.clear()

func walker(index: int, at: Vector3, destination: StringName) -> CharacterBody3D:
	var resident: CharacterBody3D = population.residents[index]
	resident.activate(at)
	resident.stops_before_indoor = 1000
	resident.social_cooldown = 1000
	resident.go_to(destination)
	return resident

func shot(label: String, from: Vector3, to: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 45
	camera.global_position = from
	camera.look_at(to)
	camera.current = true
	await ticks(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/routing_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.world_memory_enabled = false
	root.add_child(world)
	population = world.population
	population.population_seed = 1893
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.player.set_physics_process(false)
	world.controls.set_gameplay_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await ticks(20)
	clear_population()
	world.player.position = population.points[&"plaza_w"]
	var resident := walker(0,Vector3(-8,0.045,6),&"east_crossing")
	var arrivals_before: int = resident.arrivals
	var largest_step := 0.0
	for frame in range(30*hz):
		var before := resident.position
		await ticks(1)
		largest_step = maxf(largest_step,resident.position.distance_to(before))
		if resident.arrivals>arrivals_before: break
	check(resident.arrivals>arrivals_before and resident.position.x>17,"A pedestrian passes a player-occupied intermediate waypoint and reaches the far destination")
	check(largest_step<0.30 and is_equal_approx(resident.speed,1.35),"Route recovery uses ordinary physical walking without teleporting or changing speed")
	clear_population()
	var group: Array[CharacterBody3D] = []
	var counts: Dictionary = {}
	for i in range(8):
		var angle := i*TAU/8.0
		var npc := walker(i,world.player.position+Vector3(cos(angle),0,sin(angle))*4,&"plaza_w")
		group.append(npc)
		counts[npc] = npc.arrivals
	population.rebuild_neighbours()
	var arrived: Dictionary = {}
	var deepest := 0.0
	var excluded: Array[RID] = [world.player.get_rid(),world.sparring_partner.get_rid()]
	for frame in range(25*hz):
		await ticks(1)
		for npc: CharacterBody3D in group:
			if npc.arrivals>counts[npc]: arrived[npc] = true
			if frame%hz==0: deepest = maxf(deepest,Contacts.depth(npc,excluded))
		if arrived.size()==8: break
	check(arrived.size()==8,"Eight pedestrians complete an occupied public stop instead of orbiting it indefinitely")
	check(deepest<0.02,"Crowd recovery keeps all pedestrian bodies outside solid architecture")
	await shot("crowd",Vector3(3,5,15),Vector3(-3.5,1,6))
	await ticks(30*hz)
	var departed := 0
	for npc: CharacterBody3D in group:
		if npc.position.distance_to(world.player.position)>5: departed += 1
	check(departed>=6,"Recovered pedestrians resume independent errands and disperse from the blocked stop")
	clear_population()
	# Follow the shallow diagonal off the south-west paving where the long soak
	# exposed floor snap pulling a rounded capsule into the curb behind its heel.
	var curb_index := 0
	for i in range(population.residents.size()):
		if population.residents[i].name=="Haze Fold": curb_index = i
	resident = walker(curb_index,Vector3(-45,0.165,58.6),&"south_crossing_w")
	resident.path = PackedVector3Array([Vector3(-45,0.165,58.6),Vector3(-3.5,0.045,64),Vector3(2.898959,0.045,63.39896)])
	resident.cursor = 0
	var curb_depth := 0.0
	for frame in range(30*hz):
		await ticks(1)
		curb_depth = maxf(curb_depth,Contacts.depth(resident,excluded))
		if resident.position.x> -14: break
	check(curb_depth<0.02 and resident.position.x> -14,"A shallow diagonal curb descent avoids capsule penetration (deepest %.4f m)" % curb_depth)
	clear_population()
	# A temporary solid obstacle invalidates the tempting direct bypass.
	var wall := Neon.block(world,Vector3(0,1.5,6),Vector3(0.4,3,24))
	resident = walker(0,Vector3(-8,0.045,6),&"east_crossing")
	var safe := true
	for frame in range(10*hz):
		await ticks(1)
		if frame%hz==0: safe = safe and Contacts.depth(resident,excluded)<0.02
	check(safe and resident.position.x< -0.45,"Recovery retains solid-wall clearance when the next leg cannot be shortcut")
	wall.queue_free()
	clear_population()
	await ticks(2)
	# Inspect the actual bench volume and articulated pelvis after attachment.
	var actions: Node3D = world.world_actions
	var seat: Dictionary = actions.seats[0]
	var metro: Node3D = world.get_node("CentralDistrict/Metropolis")
	var closest: Dictionary = {}
	var best := INF
	for solid: Dictionary in metro.solids:
		if solid.tag not in ["BenchSeat","QuarterBenchSeat"]: continue
		var distance: float = solid.transform.origin.distance_to(seat.point)
		if distance<best:
			best = distance
			closest = solid
	var item: Resource = Catalog.create(&"eternal_scribe_robes")
	world.player.inventory.add_item(item)
	world.loot.request_equip(world.player.inventory,&"body",item.instance_id)
	world.player.position = seat.point+seat.forward*1.1
	world.player.position.y = 0.05
	world.player.velocity = Vector3.ZERO
	world.player.set_physics_process(true)
	await ticks(10)
	check(actions.interact() and not actions.seat.is_empty(),"The adjusted bench remains reachable through the normal interaction")
	actions.apply_pose()
	await ticks(4)
	var hip: Vector3 = world.player.visual.pelvis.global_position
	var top: Vector3 = closest.transform.origin+Vector3.UP*closest.collider.shape.size.y*0.5
	var forward_offset := Vector3(hip.x-top.x,0,hip.z-top.z).dot(seat.forward)
	check(absf(hip.y-top.y-0.125)<0.004 and absf(forward_offset-0.12)<0.004,"The real seated pelvis is 8 cm higher and 12 cm farther forward than the old fit")
	await shot("bench_side",hip+Vector3(0,0.9,2.8),hip+Vector3.UP*0.25)
	await shot("bench_front",hip+seat.forward*2.8+Vector3.UP*0.8,hip+Vector3.UP*0.25)
	check(actions.leave() and seat.occupant==null and not actions.attached(),"Standing releases the bench and restores the normal attachment state")
	world.queue_free()
	await ticks(2)
	print("Resident progress verification: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(0 if failures==0 else 1)
