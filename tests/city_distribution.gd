extends SceneTree
## Fixed-seed, live population density and walkability, including locked gates.
const Contacts = preload("res://tests/resident_contacts.gd")
var world: Node3D
var population: Node3D
var checks := 0
var failures := 0
var baseline := false
var seconds := 120
var custom_budget := -1
var lifecycle_only := false

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
	baseline = "--baseline" in OS.get_cmdline_user_args()
	lifecycle_only = "--lifecycle-only" in OS.get_cmdline_user_args()
	if lifecycle_only: seconds = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = int(arg.trim_prefix("--seconds="))
		if arg.begins_with("--budget="): custom_budget = int(arg.trim_prefix("--budget="))
	Engine.physics_ticks_per_second = 60
	call_deferred("run")

func density() -> Dictionary:
	var result := {"tutorial":0,"hub":0,"outer":0,"physical":0,"active":population.active_residents.size()}
	for resident: CharacterBody3D in population.active_residents:
		var radius := Vector2(resident.position.x,resident.position.z).length()
		if radius<48: result.tutorial += 1
		if maxf(absf(resident.position.x),absf(resident.position.z))<=112: result.hub += 1
		else: result.outer += 1
		if not resident.virtualized: result.physical += 1
	return result

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.district_life_enabled = false # Isolate the same original hundred identities.
	world.world_memory_enabled = false
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	population = world.population
	population.population_seed = 1893
	if custom_budget>=0:
		population.initial_outdoors = custom_budget
		population.max_outdoors = custom_budget+4
	await ticks(20)
	world.player.set_physics_process(false)
	var first := density()
	print("DISTRIBUTION START: ",JSON.stringify(first))
	if custom_budget>=0:
		check(int(first.active)==custom_budget,"Custom startup budget bounds relocated and hub residents together")
		await ticks(60*10)
		check(population.active_residents.size()<=population.max_outdoors,"Indoor exits preserve the configured total outdoor cap")
		world.queue_free()
		await ticks(2)
		print("City distribution budget verification: ",checks," checks, ",failures," failures")
		quit(1 if failures else 0)
		return
	var tutorial_total := 0
	var tutorial_peak := int(first.tutorial)
	var physical_total := 0
	var outer_min := int(first.outer)
	var unsupported := 0
	var penetrations := 0
	var journeys: Dictionary = {}
	var excluded: Array[RID] = [world.player.get_rid(),world.sparring_partner.get_rid()]
	var ember_home: Vector3 = world.sparring_partner.home
	var identities: Array = population.by_id.keys()
	for second in range(seconds):
		await ticks(60)
		var now := density()
		tutorial_total += int(now.tutorial)
		tutorial_peak = maxi(tutorial_peak,int(now.tutorial))
		physical_total += int(now.physical)
		outer_min = mini(outer_min,int(now.outer))
		for resident: CharacterBody3D in population.active_residents:
			if resident.arrivals>0: journeys[resident.profile.id] = true
			if second%10==0:
				if population.floor_at(resident.position).is_empty(): unsupported += 1
				if Contacts.depth(resident,excluded)>0.02: penetrations += 1
		if second%30==29: print("DISTRIBUTION @",second+1,"s: ",JSON.stringify(now))
	var final := density()
	print("DISTRIBUTION RESULT: ",JSON.stringify({"start":first,"final":final,"tutorial_mean":float(tutorial_total)/seconds,"tutorial_peak":tutorial_peak,"physical_mean":float(physical_total)/seconds,"outer_min":outer_min,"journeys":journeys.size(),"unsupported":unsupported,"penetrations":penetrations}))
	if not baseline:
		check(population.residents.size()==100 and population.by_id.keys()==identities,"All hundred original resident identities remain present")
		check(int(first.active)==44 and int(first.outer)==32 and int(first.hub)==12,"Startup relocates thirty-two original residents to outer-city neighborhoods and twelve around the hub")
		check(outer_min==32,"Outer residents keep independent city errands instead of commuting back to tutorial lobbies")
		# Baseline: 34.32 average / 42 peak at the same seed and observer. Leave
		# room for fair rotation of first-time walkers rather than repeated faces.
		check(float(tutorial_total)/seconds<=18 and tutorial_peak<=24,"Tutorial-area density remains substantially below the previous crowded hub")
		check(float(physical_total)/seconds<=32,"The unchanged distance system limits nearby bodies after actual redistribution")
		check(unsupported==0 and penetrations==0,"Original and relocated residents retain supported paths without embedded bodies")
		if not lifecycle_only: check(journeys.size()>=50,"Residents continue completing errands across the distributed neighborhoods")
		check(population.blocked_edges.is_empty() and population.failed_entrances.is_empty(),"All planned walking connections and original lobby passages pass physics validation")
		if not lifecycle_only: check(population.entrances.size()==22 and population.indoor_entries>0 and population.indoor_exits>0,"Original building visits remain live with all twenty-two real lobbies")
		var closed := true
		for gate: Node3D in world.wider_world.gates: closed = closed and not gate.opened
		check(closed and world.sparring_partner.home==ember_home,"City gates keep their progression lock and Ember keeps the tutorial position")
		var far: CharacterBody3D
		for resident: CharacterBody3D in population.active_residents:
			if maxf(absf(resident.position.x),absf(resident.position.z))>112:
				far = resident
				break
		if far!=null:
			world.player.position = far.position+Vector3(0,0,2)
			population.advance_simulation_lod(0)
			check(not far.virtualized and far.collision_layer==4 and far.visible,"Approaching a relocated resident restores their real body, visuals and interaction")
			check(population.nearest_talker()!=null,"Outer-city residents remain available through the same contextual interaction")
			var reactions: Node3D = world.theft_reactions
			var original_neighborhood: StringName = far.profile.neighborhood
			var original_home: StringName = far.profile.home
			for i in range(3): reactions.react(far,true)
			var key: String = reactions.key_for(far)
			check(reactions.begin_fighter(key),"A relocated resident uses the existing retaliation combat adapter")
			population.service_indoors(120)
			check(not far.active and is_inf(far.indoor_left),"Combat reservation cannot respawn a relocated civilian through a hub lobby")
			if reactions.fighters.has(key):
				var fighter: CharacterBody3D = reactions.fighters[key]
				fighter.controls.stop()
				fighter.receive_hit(5000,world.player.combat_point(),world.player,{"parryable":true})
				await ticks(3)
				world.player.position = population.points[original_home]+Vector3(0,0,5)
				reactions.entries[key].respawn = 0.1
				await ticks(60)
			check(far.active and far.profile.neighborhood==original_neighborhood and population.place_neighborhood[population.nearest_id(far.position)]==original_neighborhood,"Combat defeat restores the same resident to their outer-city home and routine")
			check(not reactions.entries[key].dead and reactions.entries[key].anger==0 and population.active_residents.count(far)==1,"Relocated civilian reconstitution clears anger without duplicating their body")
			far.deactivate()
			population.active_residents.erase(far)
			far.indoor_left = 0
			world.player.position = Vector3(0,0.1,8)
			world.camera_rig.set_physics_process(false)
			world.camera_rig.camera.reparent(world)
			world.camera_rig.camera.global_position = Vector3(0,4,8)
			world.camera_rig.camera.look_at(Vector3(0,2,0))
			await ticks(3)
			population.service_indoors(0)
			check(far.active and population.place_neighborhood[population.nearest_id(far.position)]==original_neighborhood,"A delayed street placement retries its own neighborhood rather than its retained hub lobby")
	world.queue_free()
	await ticks(2)
	print("City distribution verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
