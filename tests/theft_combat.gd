extends SceneTree
const Intent = preload("res://tests/city_life.gd").Intent
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Library = preload("res://scripts/weapon_library.gd")
var world: Node3D
var actor: CharacterBody3D
var controls: Node
var life: Node3D
var reactions: Node3D
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func person(id: int, at: Vector3, attitude: String) -> CharacterBody3D:
	var profile: Dictionary = life.profile_for(id)
	profile.attitude = attitude
	var record := {"id":id,"profile":profile,"point":at,"spawn":at,"route":PackedVector3Array([at,at+Vector3(0,0,2)]),"cursor":1,"meetings":0,"checked":true,"valid":true}
	life.resident_records.append(record)
	var source: CharacterBody3D = life.spawn_person(record)
	source.wait = 120
	return source

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.greefer.think_enabled = false
	await frames(5)
	life = world.district_life
	reactions = world.theft_reactions
	reactions.max_fighters = 0 # Observe the theft first, then explicitly test escalation.
	life.set_physics_process(false)
	world.population.set_physics_process(false)
	for source: CharacterBody3D in world.population.active_residents.duplicate(): source.deactivate()
	world.population.active_residents.clear()
	for source: CharacterBody3D in life.people.values(): source.queue_free()
	life.people.clear()
	for vehicle: CharacterBody3D in life.vehicles.values(): vehicle.queue_free()
	life.vehicles.clear()
	controls = Intent.new()
	root.add_child(controls)
	actor.controls = controls
	world.inventory_session.controls = controls
	world.camera_rig.controls = controls
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	actor.global_position = Vector3(194,0.05,128)
	actor.velocity = Vector3.ZERO
	await frames(3)
	var calm := person(9000,Vector3(196,0.04,131),"friendly")
	var distant := person(9001,Vector3(250,0.04,128),"dismissive")
	var hidden := person(9002,Vector3(182,0.04,128),"dismissive")
	var wall := StaticBody3D.new()
	world.add_child(wall)
	wall.position = Vector3(187,1.5,128)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4,3,5)
	shape.shape = box
	wall.add_child(shape)
	var vehicle := Vehicle.new()
	vehicle.life = life
	var driver: Dictionary = life.profile_for(4,true)
	driver.attitude = "dismissive"
	vehicle.record = {"id":10000,"kind":"car","point":Vector3(192,0.04,128),"yaw":0.0,"traffic":true,"taken":false,"route":PackedVector3Array([Vector3(192,0.04,128),Vector3(192,0.04,128)]),"cursor":0,"color":Color.CYAN,"driver":driver}
	life.add_child(vehicle)
	life.vehicles[10000] = vehicle
	vehicle.set_physics_process(false)
	await frames(4)
	check(world.world_actions.board(vehicle),"Actual occupied-car interaction triggers theft")
	var owner: CharacterBody3D
	for source: CharacterBody3D in life.people.values():
		if source!=calm and source!=distant and source!=hidden: owner = source
	check(owner!=null and not vehicle.has_driver,"Displaced driver survives as the same profiled resident")
	var key: String = reactions.key_for(owner)
	check(reactions.entries.has(key) and reactions.entries[key].anger>0 and reactions.entries[key].line.to_lower().contains("human"),"Owner berates the human and gains personal anger")
	check(reactions.entries.has(reactions.key_for(calm)) and reactions.entries[reactions.key_for(calm)].anger<100,"A calmer witness reacts without automatically becoming an enemy")
	check(not reactions.entries.has(reactions.key_for(distant)) and not reactions.entries.has(reactions.key_for(hidden)),"Distant and occluded residents do not read theft through walls")
	if "--capture" in OS.get_cmdline_user_args():
		await frames(ceili(hz*0.35))
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/theft_reaction.png")
	var anger: float = reactions.entries[key].anger
	check(world.world_actions.leave(),"Stolen car retains its safe exit")
	actor.global_position = vehicle.global_position+Vector3(2,0.05,0)
	await frames(3)
	check(world.world_actions.board(vehicle) and reactions.entries[key].anger==anger,"Reentering the same stolen car does not duplicate the theft event")
	world.world_actions.leave()
	wall.queue_free()
	vehicle.queue_free()
	life.vehicles.clear()
	await frames(3)
	reactions.react(owner,true)
	reactions.max_fighters = 3
	check(reactions.entries[key].anger==100 and reactions.begin_fighter(key),"Accumulated anger crosses a configurable threshold into combat")
	var fighter: CharacterBody3D = reactions.fighters[key]
	fighter.controls.stop()
	check(not owner.visible and owner.record.combat and fighter.is_in_group("combat_targets") and actor.get_collision_layer_value(2),"One civilian is replaced by one targetable fighter without duplicate bodies")
	check(fighter.health==1000 and fighter.weapon_combat.rules.defender_exhaustion_multiplier==0.25 and fighter.female_shape!=null,"Fighter preserves identity/silhouette and shares base HP and defender exhaustion")
	actor.global_position = Vector3(200,0.05,130)
	actor.velocity = Vector3.ZERO
	fighter.global_position = Vector3(200,0.05,128)
	fighter.velocity = Vector3.ZERO
	fighter.target_lock.select(actor)
	fighter.camera_rig.yaw = PI
	fighter.combat.selected_slot = &"down"
	fighter.combat.sheathed = false
	fighter.weapon_combat.sync_rig()
	await frames(3)
	var attack := Library.move(&"down",&"attack_right")
	fighter.combat.blocking = true
	fighter.weapon_combat.parry_remaining = 0
	var applied: float = fighter.receive_hit(80,actor.combat_point(),actor,attack)
	check(applied>0 and applied<80 and actor.weapon_combat.psi_meter>0 and fighter.weapon_combat.psi_meter>0,"Civilian guard uses normal chip damage and strain on both participants")
	var before: float = fighter.health
	var strain: float = fighter.weapon_combat.psi_meter
	fighter.weapon_combat.parry_remaining = 0.18
	check(fighter.receive_hit(80,actor.combat_point(),actor,attack)==0 and fighter.health==before and fighter.weapon_combat.psi_meter==strain and actor.weapon_combat.stagger_remaining>0,"Timed civilian parry prevents damage/defender strain and staggers the attacker")
	actor.weapon_combat.clear_stagger()
	fighter.combat.blocking = false
	fighter.weapon_combat.parry_remaining = 0
	actor.velocity = Vector3(10,0,0)
	actor.weapon_combat._pulse_targets.clear()
	before = fighter.health
	actor.weapon_combat.resolve_strike(attack,0,actor.combat_point(),[{"collider":fighter,"rid":fighter.get_rid(),"shape":0}],false)
	check(is_equal_approx(before-fighter.health,float(attack.damage)*actor.weapon_combat.damage_multiplier(10)),"Momentum damage reaches the civilian through the existing strike pipeline")
	actor.velocity = Vector3.ZERO
	actor.global_position = Vector3(200,0.05,132)
	var cover := Vehicle.new()
	cover.life = life
	cover.record = {"id":10001,"kind":"car","point":Vector3(200,0.04,130),"yaw":PI*0.5,"traffic":false,"taken":false,"color":Color.CYAN,"driver":driver}
	life.add_child(cover)
	cover.set_physics_process(false)
	await frames(3)
	before = fighter.health
	var long_attack := attack.duplicate(true)
	long_attack.reach = 6
	actor.weapon_combat.resolve_strike(long_attack,1,actor.combat_point(),[{"collider":fighter,"rid":fighter.get_rid(),"shape":0}],false)
	check(fighter.health==before,"Physical vehicle bodies block shared combat strikes")
	cover.queue_free()
	await frames(2)
	actor.global_position = Vector3(200,0.05,130)
	actor.velocity = Vector3.ZERO
	fighter.weapon_combat.health = 1000
	fighter.weapon_combat.clear_stagger()
	fighter.controls.start()
	actor.weapon_combat.health = 1000
	await frames(hz*3)
	check(actor.health<1000 and fighter.controls.decisions>0,"Enraged resident can genuinely attack and damage the player")
	if "--capture" in OS.get_cmdline_user_args():
		world.camera_rig.yaw = 0.5
		world.camera_rig.reset_follow()
		await frames(4)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/theft_combat.png")
	fighter.controls.stop()
	fighter.dodge.cancel()
	fighter.combat.blocking = false
	fighter.weapon_combat.parry_remaining = 0
	reactions.respawn_delay = 0.5
	var spawn_point: Vector3 = reactions.entries[key].spawn
	actor.global_position = spawn_point
	actor.velocity = Vector3.ZERO
	var profile_name: String = owner.profile.name
	fighter.receive_hit(5000,actor.combat_point(),actor,{"parryable":true})
	await frames(3)
	check(not reactions.fighters.has(key) and reactions.entries[key].dead and not owner.visible,"Lethal damage removes the fighter once and schedules civilian respawn")
	await frames(hz)
	check(not owner.visible,"An occupied spawn delays respawn rather than materializing inside the player")
	actor.global_position = Vector3(210,0.05,128)
	await frames(hz)
	check(owner.visible and owner.profile.name==profile_name and owner.global_position.distance_to(spawn_point)<0.2 and not owner.record.combat and reactions.entries[key].anger==0,"Defeated NPC returns to its own spawn and identity, with anger reset")
	check(not actor.get_collision_layer_value(2) and not actor.is_in_group("combat_targets"),"Last street fight releases its player hurt/target registration")
	var active: Array[String] = []
	for i in range(4):
		var source := person(9100+i,Vector3(210+i*2,0.04,132),"dismissive")
		reactions.react(source,true)
		reactions.react(source,true)
		var id: String = reactions.key_for(source)
		if reactions.begin_fighter(id): active.append(id)
	check(active.size()==3 and reactions.fighters.size()==3,"Street hostility respects the simultaneous fighter budget")
	actor.global_position = world.sparring_partner.home+Vector3(-2,0,0)
	actor.velocity = Vector3.ZERO
	world.sparring_duel.start()
	check(not reactions.can_fight() and reactions.fighters[active[0]].receive_hit(50,actor.combat_point(),actor)==0,"Ember's duel retains its existing isolated combat rules")
	await frames(ceili(hz*0.4))
	world.sparring_duel.finish(false)
	await frames(3)
	check(reactions.fighters.is_empty(),"Street opponents disengage when a protected encounter begins")
	for entry: Dictionary in reactions.entries.values(): entry.anger = 0
	# Existing hub citizens use the same adapter without duplicating lobby exits.
	var hub: CharacterBody3D = world.population.residents[0]
	hub.activate(Vector3(210,0.04,134))
	hub.wait = 120
	actor.global_position = Vector3(210,0.05,130)
	reactions.react(hub,true)
	reactions.react(hub,true)
	reactions.react(hub,true)
	var hub_key: String = reactions.key_for(hub)
	check(reactions.begin_fighter(hub_key) and world.population.reserved_outdoors==1 and not hub.active,"Hub citizen reserves its outdoor slot while fighting")
	world.population.service_indoors(20)
	check(not hub.active and is_inf(hub.indoor_left) and world.population.active_residents.size()+world.population.reserved_outdoors<=world.population.max_outdoors,"Building scheduler cannot duplicate a fighter or exceed its outdoor budget")
	if reactions.fighters.has(hub_key):
		reactions.fighters[hub_key].controls.stop()
		reactions.finish_fighter(hub_key)
	await frames(3)
	check(hub.active and world.population.reserved_outdoors==0 and world.population.active_residents.count(hub)==1,"Returning hub citizen releases the reservation and restores exactly one body")
	for entry: Dictionary in reactions.entries.values(): entry.anger = 0
	reactions.react(calm,false)
	var calm_key: String = reactions.key_for(calm)
	var anger_before: float = reactions.entries[calm_key].anger
	await frames(hz*7)
	check(reactions.entries[calm_key].anger<anger_before and not reactions.fighters.has(calm_key),"Unprovoked anger cools after the incident instead of becoming permanent hostility")
	var hothead := person(9200,actor.global_position+Vector3(3,0,0),"dismissive")
	reactions.react(hothead,true)
	reactions.react(hothead,true)
	var hot_key: String = reactions.key_for(hothead)
	await frames(hz*2)
	check(reactions.fighters.has(hot_key),"Enraged residents automatically begin fighting after a readable shouting delay")
	print("THEFT COMBAT: ",checks," checks, ",failures," failures at ",hz," Hz")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	quit(1 if failures else 0)
