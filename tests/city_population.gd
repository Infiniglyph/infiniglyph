extends SceneTree
const Contacts = preload("res://tests/resident_contacts.gd")
## Real city routes, independent routines, social memory and existing input paths.
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

func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(2)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/population_"+label+".png")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	population = world.population
	population.population_seed = 1893
	await ticks(20)
	check(population.ready_for_visitors and population.residents.size()==100,"One hundred distinct residents belong to the real city")
	print("PEDESTRIAN GRAPH: ",population.points.size()," places, ",population.edges.size()," edges; rejected: ",population.blocked_edges)
	check(population.blocked_edges.is_empty(),"Every planned street connection passes floor and capsule clearance probes")
	var reachable := 0
	var total := 0
	for from: StringName in population.points:
		for to: StringName in population.points:
			total += 1
			if not population.graph.get_id_path(population.point_ids[from],population.point_ids[to]).is_empty(): reachable += 1
	check(reachable==total,"All %d destination pairs are connected across the public street network" % total)
	var social_reached: Dictionary = {}
	var pending: Array = [population.residents[0].profile.id]
	while not pending.is_empty():
		var id: StringName = pending.pop_back()
		if social_reached.has(id): continue
		social_reached[id] = true
		for contact: StringName in population.by_id[id].profile.contacts: pending.append(contact)
	check(social_reached.size()==100,"Named acquaintances connect the whole populace into one social network")
	var attitudes: Dictionary = {}
	var bodies := true
	for resident: CharacterBody3D in population.residents:
		attitudes[resident.profile.attitude] = true
		bodies = bodies and resident.collision_layer==(4 if resident.active else 0) and resident.collision_mask==(5 if resident.active else 0) and not resident.is_in_group("combat_targets")
	check(attitudes.size()==5,"Curiosity, friendship, pragmatism, prejudice and indifference coexist")
	check(bodies and world.player.get_collision_mask_value(3),"Residents have physical capsules without entering combat target or architectural query layers")
	check(population.residents[0].visual.get_child_count()==2,"Each pedestrian uses two mesh batches with no per-NPC retrieval service")
	# Two real acquaintances meet on a clear street; the social director notices.
	var a: CharacterBody3D = population.residents[0]
	var b: CharacterBody3D = population.residents[1]
	for resident: CharacterBody3D in [a,b]:
		resident.go_to(&"north_w")
		resident.activate(population.points[&"north_w"]+Vector3(-0.7 if resident==a else 0.7,0,0))
		resident.wait = 5
		resident.social_cooldown = 0
		resident.stops_before_indoor = 1000
	population.rebuild_neighbours()
	await ticks(ceili(3.5*hz))
	check(population.social_events>0,"Acquaintances greet and converse without player interaction")
	check(a.conversations>0 and a.partner_id==a.profile.contacts[0],"A real social encounter records who the resident met")
	var before: Dictionary = {}
	for resident: CharacterBody3D in population.residents: before[resident.profile.id] = resident.position
	world.start_menu.open_menu()
	await ticks(ceili(9*hz))
	var movers := 0
	for resident: CharacterBody3D in population.residents:
		if resident.position.distance_to(before[resident.profile.id])>1: movers += 1
	check(not paused and movers>=10,"Independent pedestrian routines continue behind Start/Settings")
	world.start_menu.close_menu()
	world.inventory_session.ui.open_menu()
	var old_position: Dictionary = {}
	for resident: CharacterBody3D in population.active_residents: old_position[resident.profile.id] = resident.position
	await ticks(ceili(3*hz))
	var inventory_movers := 0
	for resident: CharacterBody3D in population.active_residents:
		if old_position.has(resident.profile.id) and resident.position.distance_to(old_position[resident.profile.id])>0.25: inventory_movers += 1
	check(not paused and inventory_movers>5,"Residents continue moving behind Select/View inventory")
	world.inventory_session.ui.close_menu()
	# Stage an interaction at a clear existing boulevard node, not through UI internals.
	a.position = population.points[&"north_w"]
	a.velocity = Vector3.ZERO
	a.path.clear()
	a.wait = 30
	a.social_cooldown = 30
	world.player.position = a.position+Vector3(0,0,2)
	world.player.velocity = Vector3.ZERO
	await ticks(8)
	check(population.nearest_talker()==a and world.inventory_session.can_talk(),"Nearby visible residents enter the existing contextual G/RT interaction")
	await key(KEY_G)
	check(a.visits==1 and world.inventory_session.resident_dialogue.text.begins_with("ILEX"),"G speaks to the named resident and shows their individual greeting")
	world.controls.set_right_trigger(0)
	world.controls.set_right_trigger(1)
	await ticks(3)
	check(a.visits==2 and "came back" in world.inventory_session.resident_dialogue.text,"RT uses the same interaction and remembers a previous meeting")
	world.controls.set_right_trigger(0)
	await key(KEY_G)
	check(a.visits==3 and "Mica" in world.inventory_session.resident_dialogue.text,"Repeat dialogue refers to an actual named acquaintance")
	check(world.controls.gameplay_enabled and not paused,"Resident conversation remains a live, nonblocking street exchange")
	check(world.inventory_session.resident_dialogue.visible and not population.residents[1].caption.visible,"A readable local dialogue panel takes precedence over nearby ambient speech")
	await shot("conversation")
	# Physical personal space: an idle civilian yields instead of pinning the player.
	var original_position: Vector3 = a.position
	world.player.position = a.position+Vector3(0.8,0,0)
	var player_start: Vector3 = world.player.position
	await ticks(ceili(0.8*hz))
	check(a.position.distance_to(original_position)>0.3 and Vector2(world.player.position.x-player_start.x,world.player.position.z-player_start.z).length()<0.15,"An idle resident steps out of the player's personal space without pushing the player")
	# A wall blocks interaction; no talking through a building.
	var actor_position: Vector3 = world.player.position
	var resident_position: Vector3 = a.position
	world.player.position = Vector3(16.5,0.15,28)
	a.position = Vector3(18.5,0.15,28)
	check(not population.visible_between(world.player.position,a.position),"Architecture occludes civilian sight and interaction")
	world.player.position = actor_position
	a.position = resident_position
	# Only an observable attack triggers a reaction, not a queued input.
	for resident: CharacterBody3D in population.residents: resident.reaction_cooldown = 0
	world.controls._request(&"action",&"attack_right")
	check(a.reaction_time==0,"Unobserved input requests do not grant civilians foreknowledge")
	await ticks(ceili(0.45*hz))
	check(a.reaction_time>0 and population.observed_events>0,"Visible nearby combat makes residents seek room on reachable streets")
	check(a.goal in population.points and not a.path.is_empty(),"A fight reaction chooses a navigable destination rather than a random point in a wall")
	world.player.weapon_combat.cancel()
	world.player.position = world.sparring_partner.home+Vector3(-2,0,0)
	a.position = world.player.position+Vector3(0,0,1.2)
	a.velocity = Vector3.ZERO
	a.wait = 20
	await ticks(4)
	var visits_before: int = a.visits
	world.inventory_session.interact()
	check(world.sparring_duel.dialogue_open and a.visits==visits_before,"An adjacent resident cannot steal Ember's established sparring interaction")
	world.sparring_duel.answer(false)
	a.go_to(&"north_w")
	world.player.respawn()
	# Let residents visit actual destinations, including curb transitions and courts.
	var below_floor := 0
	var penetrations := 0
	var excluded: Array[RID] = [world.player.get_rid(),world.sparring_partner.get_rid()]
	var deepest := 0.0
	for i in range(ceili(160*hz)):
		await ticks(1)
		if i%hz==0:
			for resident: CharacterBody3D in population.active_residents:
				if resident.position.y< -0.1: below_floor += 1
				var depth: float = Contacts.depth(resident,excluded)
				deepest = maxf(deepest,depth)
				if depth>0.02:
					penetrations += 1
					if penetrations<5: print("DEEP CONTACT: ",resident.name," ",resident.position," depth ",depth)
	var arrived := 0
	var visits := 0
	var current_states := true
	for resident: CharacterBody3D in population.residents:
		if resident.arrivals>0: arrived += 1
		else: print("NO ARRIVAL: ",resident.name," at ",resident.position," -> ",resident.goal," cursor ",resident.cursor,"/",resident.path.size()," state ",resident.state)
		visits += resident.arrivals
		if resident.wait<=0 and resident.state in ["talking","chatting"]: current_states = false
	print("ROUTINE SOAK: ",arrived," residents arrived; ",visits," total stops; ",population.social_events," conversations; floor errors ",below_floor,"; overlaps ",penetrations," deepest ",deepest)
	check(arrived>=40 and visits>=80,"The expanded populace completes independent journeys and continues to subsequent stops")
	check(below_floor==0 and penetrations==0,"The routine soak finds no falls or embedded bodies (2 cm contact tolerance)")
	check(current_states,"Residents resume their travel state after conversation ends")
	check(world.player.health==1000 and world.sparring_partner.health==1000,"Civilian activity does not alter player or sparring health")
	await shot("streets")
	world.queue_free()
	await ticks(2)
	print("City population verification: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
