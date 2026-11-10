extends SceneTree
const Contacts = preload("res://tests/resident_contacts.gd")
var world: Node3D
var population: Node3D
var checks := 0
var failures := 0
var hz := 60
var seconds := 180

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
		if arg.begins_with("--seconds="): seconds = int(arg.trim_prefix("--seconds="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.wider_world_enabled = not "--without-expansion" in OS.get_cmdline_user_args()
	# A local seed isolates population randomness from combat and loot randomness.
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	population = world.population
	population.population_seed = 1893
	await ticks(20)
	check(population.ready_for_visitors and population.residents.size()==100 and population.by_id.size()==100,"One hundred unique resident identities are registered")
	print("FLOW GRAPH: ",population.points.size()," nodes, ",population.edges.size()," edges; entrances ",population.entrances.size()," failed ",population.failed_entrances," rejected ",population.blocked_edges)
	check(population.failed_entrances.is_empty() and population.entrances.size()==22,"All twenty-two building lobbies connect to physical pedestrian routes")
	check(population.blocked_edges.is_empty(),"All planned pedestrian connections pass actual floor and capsule probes")
	var disconnected := 0
	for id: StringName in population.points:
		if population.graph.get_id_path(population.point_ids[&"plaza_w"],population.point_ids[id]).is_empty(): disconnected += 1
	check(disconnected==0,"Every building and public destination belongs to one reachable network")
	var colors: Dictionary = {}
	var has_light := true
	for resident: CharacterBody3D in population.residents:
		colors[resident.profile.color_name] = true
		if resident.profile.color_name=="orange" and resident.light==null: has_light = false
	check(colors.size()==11 and has_light,"All eleven requested color families appear and orange bodies have local lights")
	var initial: int = population.active_residents.size()
	check(initial>=35 and initial<=population.initial_outdoors,"Startup pedestrians are distributed while other residents start indoors")
	var cells: Dictionary = {}
	for resident: CharacterBody3D in population.active_residents:
		var cell := Vector2i(floori(resident.position.x/16),floori(resident.position.z/16))
		cells[cell] = true
	check(cells.size()>=14,"Initial residents occupy many city blocks instead of one spawn mass")
	var max_active: int = initial
	var bad_floor := 0
	var overlaps := 0
	var max_crowd := 0
	var excluded: Array[RID] = [world.player.get_rid(),world.sparring_partner.get_rid()]
	var deepest := 0.0
	var all_exits: Dictionary = {}
	var all_entries: Dictionary = {}
	var ever_outside: Dictionary = {}
	var awake_during_menu := false
	world.start_menu.open_menu()
	var first_position: Vector3 = population.active_residents[0].position
	for second in range(seconds):
		await ticks(hz)
		if second==5:
			awake_during_menu = population.active_residents[0].position.distance_to(first_position)>0.2 and not paused
			world.start_menu.close_menu()
		max_active = maxi(max_active,population.active_residents.size())
		var crowd: Dictionary = {}
		for resident: CharacterBody3D in population.active_residents:
			ever_outside[resident.profile.id] = true
			if resident.position.y< -0.1: bad_floor += 1
			var depth: float = Contacts.depth(resident,excluded)
			deepest = maxf(deepest,depth)
			if depth>0.02:
				overlaps += 1
				if overlaps<8: print("BODY OVERLAP: ",resident.name," ",resident.position," state ",resident.state," depth ",depth)
			var cell := Vector2i(floori(resident.position.x/6),floori(resident.position.z/6))
			crowd[cell] = crowd.get(cell,0)+1
			max_crowd = maxi(max_crowd,crowd[cell])
		for id: StringName in population.entrances:
			var door: Node3D = population.entrances[id]
			if door.entries>0: all_entries[id] = true
			if door.exits>0: all_exits[id] = true
		if second%30==29: print("FLOW @",second+1,"s active ",population.active_residents.size()," entries ",population.indoor_entries," exits ",population.indoor_exits," crowd ",max_crowd)
	check(awake_during_menu,"Population routines and indoor schedules remain live behind Start")
	check(max_active<=population.max_outdoors,"An outdoor population budget prevents the hundred-person roster forming one crowd")
	check(bad_floor==0 and overlaps==0,"The flow soak finds no unsupported falls or embedded bodies (2 cm contact tolerance)")
	check(max_crowd<=10,"Pedestrians do not accumulate as a large mass in a six-metre cell")
	check(population.indoor_exits>=20 and all_exits.size()>=12,"Residents emerge on foot from many different building lobbies")
	check(population.indoor_entries>=15 and all_entries.size()>=8,"Residents return indoors through multiple physical entrances")
	check(ever_outside.size()>=90,"The exit scheduler circulates the broader roster rather than recycling one small subset")
	var dormant_ok := true
	for resident: CharacterBody3D in population.residents:
		if not resident.active and (resident.visible or resident.collision_layer!=0 or resident.is_physics_processing()): dormant_ok = false
	check(dormant_ok,"Indoor residents preserve identity without rendering or blocking the world")
	print("FLOW RESULT: active ",population.active_residents.size()," max ",max_active," distinct outside ",ever_outside.size()," entries ",population.indoor_entries," across ",all_entries.size()," doors; exits ",population.indoor_exits," across ",all_exits.size()," doors; floor ",bad_floor," overlaps ",overlaps," deepest ",deepest," max cell ",max_crowd)
	world.queue_free()
	await ticks(2)
	print("Population flow verification: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
